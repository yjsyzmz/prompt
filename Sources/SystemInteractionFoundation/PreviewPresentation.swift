enum PreviewStatus: CaseIterable, Hashable, Sendable {
    case ready
    case permissionRequired
    case secureInput
    case emptyOrUnsupported
    case staleTarget
    case writeFailed
    case recoveryUnavailable
    case hotKeyConflict
    case clipboardReadFailed
    case clipboardWriteFailed
    case targetNotWritable
}

enum PreviewUserAction: Hashable, Sendable {
    case confirmReplacement
    case copyResult
    case cancel
    case restoreOriginal
    case copyOriginal
    case openSettings
    case recheckPermission
    case useClipboard
    case retry
    case retryRegistration
    case close
}

struct PreviewButton: Equatable, Sendable {
    let action: PreviewUserAction
    let title: String
    let isEnabled: Bool
}

struct PreviewViewState: Equatable, Sendable {
    let message: String
    let buttons: [PreviewButton]
    /// FR-006／FR-007／FR-008: an actionable preview must disclose the text that
    /// was read and the exact text that would be written, before confirmation.
    /// Refusal and failure states leave both nil so that no content is shown.
    let sourceText: String?
    let resultText: String?

    init(
        message: String,
        buttons: [PreviewButton],
        sourceText: String? = nil,
        resultText: String? = nil
    ) {
        self.message = message
        self.buttons = buttons
        self.sourceText = sourceText
        self.resultText = resultText
    }

    var canConfirmReplacement: Bool {
        buttons.contains { $0.action == .confirmReplacement && $0.isEnabled }
    }
}

struct PreviewPresentationMapper {
    func viewState(for status: PreviewStatus) -> PreviewViewState {
        switch status {
        case .ready:
            return PreviewViewState(
                message: "优化结果已准备好，确认后才会替换原文。",
                buttons: [
                    PreviewButton(
                        action: .confirmReplacement,
                        title: "确认替换",
                        isEnabled: true
                    ),
                    PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                    PreviewButton(action: .cancel, title: "取消", isEnabled: true),
                ]
            )
        case .permissionRequired:
            return PreviewViewState(
                message: "需要辅助功能权限才能读取或替换目标文字。打开设置后，请前往「隐私与安全性」→「辅助功能」并启用本应用。",
                buttons: [
                    PreviewButton(action: .openSettings, title: "打开设置", isEnabled: true),
                    PreviewButton(
                        action: .recheckPermission,
                        title: "重新检测",
                        isEnabled: true
                    ),
                    PreviewButton(action: .useClipboard, title: "使用剪贴板", isEnabled: true),
                ]
            )
        case .secureInput:
            return PreviewViewState(
                message: "当前是安全输入环境，应用不会读取或处理其中的内容。",
                buttons: [
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ]
            )
        case .emptyOrUnsupported:
            return PreviewViewState(
                message: "没有可处理的文字，或当前输入位置不支持直接读取。",
                buttons: [
                    PreviewButton(action: .retry, title: "重试", isEnabled: true),
                    PreviewButton(action: .useClipboard, title: "使用剪贴板", isEnabled: true),
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ]
            )
        case .staleTarget:
            return PreviewViewState(
                message: "原输入位置已经变化，不能安全替换。",
                buttons: [
                    PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                    PreviewButton(action: .cancel, title: "取消", isEnabled: true),
                ]
            )
        case .writeFailed:
            return PreviewViewState(
                message: "未能安全替换原文，结果仍可复制。",
                buttons: [
                    PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                    PreviewButton(action: .cancel, title: "取消", isEnabled: true),
                ]
            )
        case .recoveryUnavailable:
            return PreviewViewState(
                message: "目标内容已经变化，无法直接恢复。",
                buttons: [
                    PreviewButton(action: .copyOriginal, title: "复制原文", isEnabled: true),
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ]
            )
        case .hotKeyConflict:
            return PreviewViewState(
                message: "快捷键当前不可用，可能已被其他应用占用。关闭占用它的应用后可以重新注册。",
                buttons: [
                    PreviewButton(
                        action: .retryRegistration,
                        title: "重新注册",
                        isEnabled: true
                    ),
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ]
            )
        case .clipboardReadFailed:
            return PreviewViewState(
                message: "未能读取剪贴板文字，请重新复制后重试。",
                buttons: [
                    PreviewButton(action: .useClipboard, title: "重试", isEnabled: true),
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ]
            )
        case .clipboardWriteFailed:
            return PreviewViewState(
                message: "未能复制到剪贴板，结果仍保留在预览中，可以重试。",
                buttons: [
                    PreviewButton(action: .retry, title: "重试", isEnabled: true),
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ]
            )
        case .targetNotWritable:
            return PreviewViewState(
                message: "当前输入位置已不可写入，未做任何修改，结果仍可复制。",
                buttons: [
                    PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                    PreviewButton(action: .cancel, title: "取消", isEnabled: true),
                ]
            )
        }
    }
}
