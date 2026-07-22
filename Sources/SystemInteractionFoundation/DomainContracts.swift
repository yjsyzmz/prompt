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
