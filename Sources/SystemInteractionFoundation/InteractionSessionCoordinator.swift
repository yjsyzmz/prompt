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

protocol SessionTextTargetAccessing: AnyObject {
    func replace(_ content: SessionContent) -> Bool
    func validateForRecovery(_ content: SessionContent) -> Bool
    func restore(_ content: SessionContent) -> Bool
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

    var availableActions: [SessionAction] {
        switch state {
        case .previewing(.ready):
            guard let content else {
                return []
            }
            return content.mode == .clipboardInput
                ? [.copyResult, .cancel]
                : [.confirmReplacement, .copyResult, .cancel]
        case .previewing(.writeFailed):
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
            content.mode != .clipboardInput
        else {
            return
        }

        transition(to: .applying)
        transition(
            to: target.replace(content)
                ? .recoverable
                : .previewing(.writeFailed)
        )
    }

    func recoverOriginal() {
        guard state == .recoverable, let content else {
            return
        }

        guard target.validateForRecovery(content) else {
            transition(to: .previewing(.recoveryUnavailable))
            return
        }

        if target.restore(content) {
            endSession()
        } else {
            transition(to: .previewing(.recoveryUnavailable))
        }
    }

    func copyOriginal() {
        guard
            state == .previewing(.recoveryUnavailable),
            let original = content?.source.value
        else {
            return
        }

        _ = pasteboard.writeLocalStringAfterExplicitAction(original)
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
        currentSessionID = nil
        content = nil
        if hadActiveSession {
            transition(to: .ended)
        }
    }

    private func endSession() {
        currentSessionID = nil
        content = nil
        transition(to: .ended)
    }

    private func transition(to newState: InteractionSessionState) {
        state = newState
        observer?.sessionCoordinatorDidTransition(to: newState)
    }
}
