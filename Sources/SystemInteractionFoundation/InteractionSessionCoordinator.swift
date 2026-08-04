import Foundation

typealias InteractionSessionID = UUID

enum CaptureMode: Equatable, Sendable {
    case selectedText(AXTextRange)
    case wholeField
    case clipboardInput
}

enum PreviewCapability: Equatable {
    case ready
    case writeFailed
    case recoveryUnavailable
    /// NFR-007: an authoritative validation rejection keeps its own category so
    /// that the panel can explain why nothing was written, instead of implying
    /// that a write was attempted and failed.
    case replacementRejected(DomainFailure)
}

enum InteractionSessionState: Equatable {
    case idle
    case checkingPermission
    case capturingTarget
    case previewing(PreviewCapability)
    case applying
    case recoverable
    case ended
}

enum SessionAction: Hashable {
    case confirmReplacement
    case copyResult
    case cancel
    case copyOriginal
    case close
}

struct SessionContent: Equatable {
    let source: SourceText
    let transformed: TransformedText
    let mode: CaptureMode
}

/// `plan.md` 第 129–136 行批准的契约：写入与恢复都是 `async`。同步协议加
/// `DispatchSemaphore` 桥是对该契约的偏离——它会在回读期间占住 `MainActor`，
/// 使会话结束、面板关闭与新会话抢占都无法被处理（T-065）。
///
/// `@MainActor`：`plan.md` 第 52 行把 UI 与 Coordinator 放在主 actor，AX 引用由
/// gateway actor 串行拥有。因此本协议的实现留在主 actor，真正的挂起发生在它内部
/// `await` gateway 的那一刻——那一刻主 actor 被释放。
@MainActor
protocol SessionTextTargetAccessing: AnyObject {
    func replace(_ content: SessionContent) async -> Result<Void, DomainFailure>
    func validateForRecovery(_ content: SessionContent) async -> Bool
    func restore(_ content: SessionContent) async -> Bool
}

protocol SessionPasteboardAccessing: AnyObject {
    func writeLocalStringAfterExplicitAction(_ text: String) -> Bool
}

protocol SessionStateObserving: AnyObject {
    func sessionCoordinatorDidTransition(to state: InteractionSessionState)
}

@MainActor
final class InteractionSessionCoordinator {
    private let target: SessionTextTargetAccessing
    private let pasteboard: SessionPasteboardAccessing
    private weak var observer: SessionStateObserving?
    private var content: SessionContent?

    private(set) var state: InteractionSessionState = .idle
    private(set) var currentSessionID: InteractionSessionID?

    /// T-065：`plan.md` 第 387 行要求会话结束时取消异步任务。句柄同时让测试能确定性
    /// 地等待在途写入／恢复结束，而不是靠 `Task.yield()` 猜调度。
    private(set) var applyWork: Task<Void, Never>?
    private(set) var recoverWork: Task<Void, Never>?

    var availableActions: [SessionAction] {
        switch state {
        case .previewing(.ready):
            guard let content else {
                return []
            }
            return content.mode == .clipboardInput
                ? [.copyResult, .cancel]
                : [.confirmReplacement, .copyResult, .cancel]
        case .previewing(.writeFailed), .previewing(.replacementRejected):
            return [.copyResult, .cancel]
        case .previewing(.recoveryUnavailable):
            return [.copyOriginal, .close]
        default:
            return []
        }
    }

    init(
        target: SessionTextTargetAccessing,
        pasteboard: SessionPasteboardAccessing,
        observer: SessionStateObserving
    ) {
        self.target = target
        self.pasteboard = pasteboard
        self.observer = observer
    }

    @discardableResult
    func beginDirectSession() -> InteractionSessionID {
        replaceCurrentSession()
        let sessionID = InteractionSessionID()
        currentSessionID = sessionID
        transition(to: .checkingPermission)
        return sessionID
    }

    @discardableResult
    func beginClipboardSession(
        source: SourceText,
        transformed: TransformedText
    ) -> InteractionSessionID {
        replaceCurrentSession()
        let sessionID = InteractionSessionID()
        currentSessionID = sessionID
        content = SessionContent(
            source: source,
            transformed: transformed,
            mode: .clipboardInput
        )
        transition(to: .previewing(.ready))
        return sessionID
    }

    func permissionResolved(
        granted: Bool,
        for sessionID: InteractionSessionID
    ) {
        guard
            granted,
            sessionID == currentSessionID,
            state == .checkingPermission
        else {
            return
        }

        transition(to: .capturingTarget)
    }

    func captureCompleted(
        source: SourceText,
        transformed: TransformedText,
        mode: CaptureMode,
        for sessionID: InteractionSessionID
    ) {
        guard
            sessionID == currentSessionID,
            state == .capturingTarget,
            mode != .clipboardInput
        else {
            return
        }

        content = SessionContent(
            source: source,
            transformed: transformed,
            mode: mode
        )
        transition(to: .previewing(.ready))
    }

    func confirmReplacement() {
        guard
            state == .previewing(.ready),
            let content,
            let sessionID = currentSessionID,
            content.mode != .clipboardInput
        else {
            return
        }

        transition(to: .applying)
        // T-065: the await releases `MainActor` for the whole write and readback,
        // so a close, cancel or new session raised meanwhile is actually served.
        applyWork = Task { [weak self] in
            guard let self else {
                return
            }
            let outcome = await self.target.replace(content)
            self.applyCompleted(outcome, for: sessionID)
        }
    }

    /// `plan.md` 第 55 行与并发规则：异步结果返回时必须再次匹配当前 session ID，
    /// 旧结果直接丢弃。取消后回来的结果**不得**进入 `recoverable`——那会把一次
    /// 未被承认的写入变成可恢复状态。
    private func applyCompleted(
        _ outcome: Result<Void, DomainFailure>,
        for sessionID: InteractionSessionID
    ) {
        guard
            !Task.isCancelled,
            sessionID == currentSessionID,
            state == .applying
        else {
            return
        }

        switch outcome {
        case .success:
            transition(to: .recoverable)
        case .failure(.writeFailed):
            // The only failure that actually reached the setter or its readback.
            transition(to: .previewing(.writeFailed))
        case .failure(let failure):
            // Rejected before any write: keep the specific reason.
            transition(to: .previewing(.replacementRejected(failure)))
        }
    }

    func recoverOriginal() {
        guard
            state == .recoverable,
            let content,
            let sessionID = currentSessionID
        else {
            return
        }

        recoverWork = Task { [weak self] in
            guard let self else {
                return
            }
            guard await self.target.validateForRecovery(content) else {
                self.recoveryCompleted(restored: false, for: sessionID)
                return
            }
            let restored = await self.target.restore(content)
            self.recoveryCompleted(restored: restored, for: sessionID)
        }
    }

    private func recoveryCompleted(
        restored: Bool,
        for sessionID: InteractionSessionID
    ) {
        guard
            !Task.isCancelled,
            sessionID == currentSessionID,
            state == .recoverable
        else {
            return
        }

        if restored {
            endSession()
        } else {
            transition(to: .previewing(.recoveryUnavailable))
        }
    }

    /// Returns whether the explicit copy reached the pasteboard. A no-op in a
    /// state that does not offer the action is not reported as a failure.
    @discardableResult
    func copyOriginal() -> Bool {
        guard
            state == .previewing(.recoveryUnavailable),
            let original = content?.source.value
        else {
            return true
        }

        return pasteboard.writeLocalStringAfterExplicitAction(original)
    }

    func cancel() {
        guard currentSessionID != nil else {
            return
        }
        endSession()
    }

    func close() {
        guard currentSessionID != nil else {
            return
        }
        endSession()
    }

    private func replaceCurrentSession() {
        let hadActiveSession = currentSessionID != nil
        cancelInFlightWork()
        currentSessionID = nil
        content = nil
        if hadActiveSession {
            transition(to: .ended)
        }
    }

    private func endSession() {
        cancelInFlightWork()
        currentSessionID = nil
        content = nil
        transition(to: .ended)
    }

    /// `plan.md` 第 387 行：会话结束时取消异步任务。取消会传播进 gateway 的回读
    /// 循环，使其在下一次检查点立即停止，而不是耗完整个预算。
    private func cancelInFlightWork() {
        applyWork?.cancel()
        applyWork = nil
        recoverWork?.cancel()
        recoverWork = nil
    }

    private func transition(to newState: InteractionSessionState) {
        state = newState
        observer?.sessionCoordinatorDidTransition(to: newState)
    }
}
