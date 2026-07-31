import XCTest

final class PreviewStateActionTests: XCTestCase {
    func testEveryPreviewStateHasTheApprovedUnderstandableMessage() {
        let expectedMessages: [PreviewStatus: String] = [
            .ready: "优化结果已准备好，确认后才会替换原文。",
            .permissionRequired: "需要辅助功能权限才能读取或替换目标文字。打开设置后，请前往「隐私与安全性」→「辅助功能」并启用本应用。",
            .secureInput: "当前是安全输入环境，应用不会读取或处理其中的内容。",
            .emptyOrUnsupported: "没有可处理的文字，或当前输入位置不支持直接读取。",
            .staleTarget: "原输入位置已经变化，不能安全替换。",
            .writeFailed: "未能安全替换原文，结果仍可复制。",
            .recoveryUnavailable: "目标内容已经变化，无法直接恢复。",
            .hotKeyConflict: "快捷键当前不可用，可能已被其他应用占用。关闭占用它的应用后可以重新注册。",
            .clipboardReadFailed: "未能读取剪贴板文字，请重新复制后重试。",
            .clipboardWriteFailed: "未能复制到剪贴板，结果仍保留在预览中，可以重试。",
            .targetNotWritable: "当前输入位置已不可写入，未做任何修改，结果仍可复制。",
        ]

        for status in PreviewStatus.allCases {
            XCTAssertEqual(
                presentation(for: status).message,
                expectedMessages[status],
                "Unexpected copy for \(status)"
            )
        }
    }

    func testEveryPreviewStateHasTheApprovedButtonMatrix() {
        let expectedButtons: [PreviewStatus: [PreviewButton]] = [
            .ready: [
                PreviewButton(
                    action: .confirmReplacement,
                    title: "确认替换",
                    isEnabled: true
                ),
                PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                PreviewButton(action: .cancel, title: "取消", isEnabled: true),
            ],
            .permissionRequired: [
                PreviewButton(action: .openSettings, title: "打开设置", isEnabled: true),
                PreviewButton(action: .recheckPermission, title: "重新检测", isEnabled: true),
                PreviewButton(action: .useClipboard, title: "使用剪贴板", isEnabled: true),
            ],
            .secureInput: [
                PreviewButton(action: .close, title: "关闭", isEnabled: true),
            ],
            .emptyOrUnsupported: [
                PreviewButton(action: .retry, title: "重试", isEnabled: true),
                PreviewButton(action: .useClipboard, title: "使用剪贴板", isEnabled: true),
                PreviewButton(action: .close, title: "关闭", isEnabled: true),
            ],
            .staleTarget: [
                PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                PreviewButton(action: .cancel, title: "取消", isEnabled: true),
            ],
            .writeFailed: [
                PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                PreviewButton(action: .cancel, title: "取消", isEnabled: true),
            ],
            .recoveryUnavailable: [
                PreviewButton(action: .copyOriginal, title: "复制原文", isEnabled: true),
                PreviewButton(action: .close, title: "关闭", isEnabled: true),
            ],
            .hotKeyConflict: [
                PreviewButton(
                    action: .retryRegistration,
                    title: "重新注册",
                    isEnabled: true
                ),
                PreviewButton(action: .close, title: "关闭", isEnabled: true),
            ],
            .clipboardReadFailed: [
                PreviewButton(action: .useClipboard, title: "重试", isEnabled: true),
                PreviewButton(action: .close, title: "关闭", isEnabled: true),
            ],
            .clipboardWriteFailed: [
                PreviewButton(action: .retryCopy, title: "重试", isEnabled: true),
                PreviewButton(action: .close, title: "关闭", isEnabled: true),
            ],
            .targetNotWritable: [
                PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                PreviewButton(action: .cancel, title: "取消", isEnabled: true),
            ],
        ]

        for status in PreviewStatus.allCases {
            XCTAssertEqual(
                presentation(for: status).buttons,
                expectedButtons[status],
                "Unexpected buttons for \(status)"
            )
        }
    }

    func testOnlyReadyCanConfirmReplacement() {
        for status in PreviewStatus.allCases {
            let viewState = presentation(for: status)
            let confirmButtons = viewState.buttons.filter {
                $0.action == .confirmReplacement
            }

            if status == .ready {
                XCTAssertTrue(viewState.canConfirmReplacement)
                XCTAssertEqual(confirmButtons.count, 1)
                XCTAssertTrue(confirmButtons[0].isEnabled)
            } else {
                XCTAssertFalse(viewState.canConfirmReplacement)
                XCTAssertTrue(confirmButtons.isEmpty)
            }
        }
    }

    func testEveryRefusalOrFailureOffersAtLeastOneEnabledSafeNextAction() {
        let nonReadyStates = PreviewStatus.allCases.filter { $0 != .ready }

        for status in nonReadyStates {
            let viewState = presentation(for: status)

            XCTAssertFalse(viewState.buttons.isEmpty, "Missing safe action for \(status)")
            XCTAssertTrue(
                viewState.buttons.contains(where: \.isEnabled),
                "No enabled safe action for \(status)"
            )
        }
    }

    func testVisibleCopyContainsNoRawErrorCodeOrSensitiveContent() {
        let forbiddenFragments = [
            "SYNTHETIC-001-sensitive",
            "kAXError",
            "AXError",
            "OSStatus",
            "NSPasteboard",
            "-25204",
        ]

        for status in PreviewStatus.allCases {
            let viewState = presentation(for: status)
            let visibleCopy = ([viewState.message] + viewState.buttons.map(\.title))
                .joined(separator: " ")

            XCTAssertFalse(visibleCopy.isEmpty)
            for fragment in forbiddenFragments {
                XCTAssertFalse(
                    visibleCopy.localizedCaseInsensitiveContains(fragment),
                    "Visible copy for \(status) leaked \(fragment)"
                )
            }
        }
    }

    private func presentation(for status: PreviewStatus) -> PreviewViewState {
        PreviewPresentationMapper().viewState(for: status)
    }
}
