import Foundation

struct SourceText: Equatable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }
}

struct TransformedText: Equatable, Sendable {
    let value: String
}

struct TargetSnapshot: Equatable {
    let sourceText: SourceText
    let transformedText: TransformedText
}

struct RecoverySnapshot: Equatable {
    let originalText: SourceText
    let expectedTransformedText: TransformedText
}

struct DeterministicTransformer {
    private static let marker = "【系统交互验证】\n"

    func transform(_ source: SourceText) -> TransformedText {
        TransformedText(value: Self.marker + source.value)
    }
}

/// T-054: `CaseIterable` so the rejection mapping can be proven **total**. A new
/// failure added here fails the mapping table test instead of being swallowed by
/// a `default` branch.
enum DomainFailure: Error, Equatable, CaseIterable {
    case hotKeyConflict
    case accessibilityPermissionRequired
    case secureInputActive
    case emptySource
    case unsupportedTarget
    case axTimedOut
    case axCannotComplete
    case invalidTarget
    case sourceChanged
    case attributeNotSettable
    case writeFailed
    case recoveryTargetChanged
    case pasteboardReadFailed
    case pasteboardWriteFailed
    case panelPlacementFallback
    case unknown
}

/// MUST 1: the authoritative replacement sequence has many rejection points that
/// collapse onto the same `DomainFailure` — A1–A4 all return `.invalidTarget`,
/// and both the setter and its readback return `.writeFailed`. Without a stage
/// identifier an intermittent real-world failure cannot be localised.
enum ReplacementStage: String, Equatable, Sendable {
    /// Clipboard mode has no authoritative target to write to.
    case unsupportedMode
    case applicationRunning     // A1
    case frontmostApplication   // A2
    case windowIdentity         // A3
    case elementIdentity        // A4
    case elementCapability
    case globalSecureInput
    /// Reading the current content failed, which is not the same as the content
    /// having changed.
    case contentRead
    case contentComparison      // B1
    case attributeSettable
    case setter
    case readback
    case completed
}

/// FR-013／NFR-006: a stage report carries only the stage, the failure category
/// and — for A2 alone — whether keyboard focus was on this process. It has no
/// `String` and no numeric member by construction, so neither the text nor any
/// measure derived from it can reach a log through this type.
///
/// Tasks Gate 裁决（2026-07-31）：长度字段完全删除，不允许等级化表示。代价是
/// B1 阶段只能报告「内容已变化」而无法给出量级。
struct ReplacementStageReport: Equatable, Sendable {
    let stage: ReplacementStage
    let failure: DomainFailure?
    /// Only set by the A2 stage. `true` means the focused application was this
    /// process — which is what happens when the preview panel takes keyboard
    /// focus from a real mouse click. Carries no identity beyond "is it us".
    let focusedApplicationIsSelf: Bool?

    init(
        stage: ReplacementStage,
        failure: DomainFailure? = nil,
        focusedApplicationIsSelf: Bool? = nil
    ) {
        self.stage = stage
        self.failure = failure
        self.focusedApplicationIsSelf = focusedApplicationIsSelf
    }
}

/// Recording is synchronous on purpose: the replacement sequence must not gain a
/// suspension point between the A1–A4 checks and the setter, because that would
/// widen the TOCTOU window `plan.md` already discloses.
protocol ReplacementDiagnosticsRecording: Sendable {
    func record(_ report: ReplacementStageReport)
}

/// T-058: the target-change monitor refuses a preview without ever entering the
/// replacement sequence, so no `ReplacementStage` can describe it — that is why
/// T-055 collected 22 stage records with zero A1–A4 rejections while the user
/// was being told the target had changed. This is the content-free
/// classification of *why* the captured target was judged stale.
enum StaleTargetReason: String, Equatable, Sendable, CaseIterable {
    /// A1: the target application is gone.
    case applicationTerminated
    /// A2: keyboard focus is on an application that is neither the target nor
    /// this session's own preview panel.
    case focusedApplicationChanged
    /// A3: the window identity no longer matches the capture.
    case windowIdentityChanged
    /// A4: the element identity no longer matches the capture.
    case elementIdentityChanged
    /// The observer fired but every identity check still matches. The refusal
    /// therefore cannot be attributed to a target change — this is the value
    /// that separates a real invalidation from a self-inflicted one.
    case identityIntact
    /// No retained reference for the handle, so there is nothing to compare.
    /// Reported as its own case rather than guessed at.
    case identityUnknown
}

/// FR-013／NFR-006: like `ReplacementStageReport`, this type has no `String` and
/// no numeric member by construction, so neither the captured text nor any
/// measure derived from it can reach a log through it.
struct StaleTargetDiagnosticReport: Equatable, Sendable {
    let reason: StaleTargetReason
    /// Only set for `.focusedApplicationChanged`. `true` means keyboard focus
    /// was on this process. Carries no identity beyond "is it us".
    let focusedApplicationIsSelf: Bool?

    init(
        reason: StaleTargetReason,
        focusedApplicationIsSelf: Bool? = nil
    ) {
        self.reason = reason
        self.focusedApplicationIsSelf = focusedApplicationIsSelf
    }
}

/// Deliberately separate from `ReplacementDiagnosticsRecording`: the monitor
/// path is a different path with a different vocabulary, and a spy that
/// silently ignored these records would let a green test hide a production path
/// that still emits nothing.
protocol StaleTargetDiagnosticsRecording: Sendable {
    func record(_ report: StaleTargetDiagnosticReport)
}

/// T-053: the A2 exemption approved in `plan.md:197` covers **this tool's own
/// non-activating panel**, not this process. This value carries the answer for
/// exactly one action.
///
/// It must be produced on `MainActor` at the instant a confirm or restore action
/// runs, and must never be stored as a reusable authorization: the preview panel
/// is a single instance reused across sessions, so a cached `true` would grant a
/// later session an exemption it never earned.
struct PanelFocusAuthorization: Sendable, Equatable {
    /// `true` only when the key window is, at this instant, the panel the
    /// current session is presenting.
    let currentSessionPanelIsKey: Bool

    /// The safe default. Any path that cannot prove panel ownership uses this.
    static let notOwned = PanelFocusAuthorization(currentSessionPanelIsKey: false)
}

/// Answers "is the panel I am presenting right now the key window?".
///
/// `MainActor`-isolated because the answer comes from AppKit window state, and
/// must be read at action time rather than remembered.
@MainActor
protocol PreviewPanelFocusOwnership: AnyObject {
    func currentSessionPanelIsKey() -> Bool
}

enum RecoveryAction: Equatable {
    case retryRegistration
    case openSettings
    case close
    case retry
    case useClipboard
    case copyResult
    case copyOriginal
    case continueWithoutPrecisePlacement
}

struct FailurePresentation: Equatable {
    let message: String
    let safeNextActions: [RecoveryAction]
    let isFailClosed: Bool
}

struct DomainFailureMapper {
    func presentation(for failure: DomainFailure) -> FailurePresentation {
        switch failure {
        case .hotKeyConflict:
            return failurePresentation(
                "快捷键暂时不可用，请关闭冲突应用后重试。",
                actions: [.retryRegistration]
            )
        case .accessibilityPermissionRequired:
            return failurePresentation(
                "需要辅助功能权限才能读取或替换目标文字。",
                actions: [.openSettings, .retry, .useClipboard]
            )
        case .secureInputActive:
            return failurePresentation(
                "当前是安全输入环境，应用不会读取或处理其中的内容。",
                actions: [.close]
            )
        case .emptySource:
            return failurePresentation(
                "没有可处理的文字，请输入或选择文字后重试。",
                actions: [.retry, .useClipboard, .close]
            )
        case .unsupportedTarget:
            return failurePresentation(
                "当前输入位置不支持直接读取，请改用剪贴板。",
                actions: [.useClipboard, .close]
            )
        case .axTimedOut:
            return failurePresentation(
                "目标应用没有及时响应，请重试或改用剪贴板。",
                actions: [.retry, .useClipboard]
            )
        case .axCannotComplete:
            return failurePresentation(
                "暂时无法完成目标应用操作，请改用剪贴板。",
                actions: [.useClipboard, .retry]
            )
        case .invalidTarget:
            return failurePresentation(
                "原输入位置已经失效，请复制结果或取消。",
                actions: [.copyResult, .close]
            )
        case .sourceChanged:
            return failurePresentation(
                "原文字或选区已经变化，请重新触发。",
                actions: [.retry, .copyResult]
            )
        case .attributeNotSettable:
            return failurePresentation(
                "当前输入位置不能直接替换，请复制结果。",
                actions: [.copyResult]
            )
        case .writeFailed:
            return failurePresentation(
                "未能安全替换原文，结果仍可复制。",
                actions: [.copyResult]
            )
        case .recoveryTargetChanged:
            return failurePresentation(
                "目标内容已经变化，无法直接恢复，请复制原文。",
                actions: [.copyOriginal]
            )
        case .pasteboardReadFailed:
            return failurePresentation(
                "未能读取剪贴板文字，请重新复制后重试。",
                actions: [.retry, .close]
            )
        case .pasteboardWriteFailed:
            return failurePresentation(
                "未能复制，请保留当前结果并重试。",
                actions: [.retry, .close]
            )
        case .panelPlacementFallback:
            return FailurePresentation(
                message: "无法精确定位预览，已改用安全位置。",
                safeNextActions: [.continueWithoutPrecisePlacement],
                isFailClosed: false
            )
        case .unknown:
            return failurePresentation(
                "操作未能安全完成，请关闭后重试。",
                actions: [.close, .retry]
            )
        }
    }

    private func failurePresentation(
        _ message: String,
        actions: [RecoveryAction]
    ) -> FailurePresentation {
        FailurePresentation(
            message: message,
            safeNextActions: actions,
            isFailClosed: true
        )
    }
}

enum PrivacySafeLogCategory: Equatable {
    case domainFailure
}

enum PrivacySafeLogState: Equatable {
    case previewing
}

struct PrivacySafeLogEvent: Equatable {
    let category: PrivacySafeLogCategory
    let state: PrivacySafeLogState
    let failure: DomainFailure
}
