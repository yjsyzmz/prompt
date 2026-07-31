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

enum DomainFailure: Error, Equatable {
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
/// and UTF-16 code-unit counts. It has no `String` member by construction, so no
/// captured or written text can reach a log through it.
struct ReplacementStageReport: Equatable, Sendable {
    let stage: ReplacementStage
    let failure: DomainFailure?
    /// UTF-16 length of the text the session expected to still be in place.
    let expectedLength: Int
    /// UTF-16 length actually observed, when the stage read anything at all.
    let observedLength: Int?
    /// Only set by the A2 stage. `true` means the focused application was this
    /// process — which is what happens when the preview panel takes keyboard
    /// focus from a real mouse click. Carries no identity beyond "is it us".
    let focusedApplicationIsSelf: Bool?

    init(
        stage: ReplacementStage,
        failure: DomainFailure? = nil,
        expectedLength: Int,
        observedLength: Int? = nil,
        focusedApplicationIsSelf: Bool? = nil
    ) {
        self.stage = stage
        self.failure = failure
        self.expectedLength = expectedLength
        self.observedLength = observedLength
        self.focusedApplicationIsSelf = focusedApplicationIsSelf
    }
}

/// Recording is synchronous on purpose: the replacement sequence must not gain a
/// suspension point between the A1–A4 checks and the setter, because that would
/// widen the TOCTOU window `plan.md` already discloses.
protocol ReplacementDiagnosticsRecording: Sendable {
    func record(_ report: ReplacementStageReport)
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
