import AppKit
import XCTest

/// Implementation Gate REVIEW Finding 1：有效预览必须在确认前展示读取到的原文
/// 与确定性结果（FR-006、FR-007、FR-008、US-002）。
@MainActor
final class PreviewContentDisclosureTests: XCTestCase {
    private let transformer = DeterministicTransformer()

    func testReadyPreviewDisclosesSourceTextAndDeterministicResult() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let env = DisclosureEnvironment.make(host: host)
        let expectedSource = host.selectedSegment
        let expectedResult = transformer.transform(SourceText(expectedSource))

        env.hotKey.press()
        await env.controller.captureWork?.value

        guard let state = env.presenter.lastState else {
            XCTFail("a ready preview must be presented")
            return
        }
        XCTAssertEqual(
            state.sourceText,
            expectedSource,
            "the preview must show the text that was read"
        )
        XCTAssertEqual(
            state.resultText,
            expectedResult.value,
            "the preview must show the exact text that would be written"
        )
        XCTAssertEqual(
            host.setterAttemptCount,
            0,
            "disclosing content must not write to the target"
        )
    }

    func testWholeFieldReadyPreviewDisclosesFullFieldContent() async {
        let host = SyntheticAXTextHost.wholeFieldFixture()
        let env = DisclosureEnvironment.make(host: host)
        let expectedSource = host.fullText

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertEqual(env.presenter.lastState?.sourceText, expectedSource)
        XCTAssertEqual(
            env.presenter.lastState?.resultText,
            transformer.transform(SourceText(expectedSource)).value
        )
        XCTAssertEqual(host.setterAttemptCount, 0)
    }

    /// 10,000 字符长文本必须逐字符完整进入预览状态，不得截断。
    func testLongSourceTextIsDisclosedWithoutTruncation() async {
        let unit = "SYNTHETIC-001 长文本片段。"
        let long = String(String(repeating: unit, count: 10_000 / unit.count + 1)
            .prefix(10_000))
        let host = SyntheticAXTextHost.wholeFieldFixture()
        host.replaceFullTextForTesting(long)
        let env = DisclosureEnvironment.make(host: host)

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertEqual(env.presenter.lastState?.sourceText?.count, 10_000)
        XCTAssertEqual(env.presenter.lastState?.sourceText, long)
        XCTAssertEqual(
            env.presenter.lastState?.resultText,
            transformer.transform(SourceText(long)).value
        )
    }

    /// 替换成功后的可恢复状态仍需展示原文与已写入的结果。
    func testRecoverableStateKeepsDisclosingOriginalAndResult() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let env = DisclosureEnvironment.make(host: host)
        let expectedSource = host.selectedSegment
        let expectedResult = transformer.transform(SourceText(expectedSource))

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)
        await env.controller.applyWork?.value

        XCTAssertEqual(env.presenter.lastState?.sourceText, expectedSource)
        XCTAssertEqual(env.presenter.lastState?.resultText, expectedResult.value)
    }

    /// 拒绝与失败状态不得携带内容（映射层保持无内容）。
    func testRefusalStatesCarryNoContent() {
        let mapper = PreviewPresentationMapper()

        for status in PreviewStatus.allCases where status != .ready {
            let state = mapper.viewState(for: status)
            XCTAssertNil(state.sourceText, "\(status) must not disclose content")
            XCTAssertNil(state.resultText, "\(status) must not disclose content")
        }
    }

    func testEmptyOrUnsupportedPreviewDisclosesNothing() async {
        let env = DisclosureEnvironment.make(host: .emptyFixture())

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertNil(env.presenter.lastState?.sourceText)
        XCTAssertNil(env.presenter.lastState?.resultText)
    }
}

// MARK: - Environment

@MainActor
private struct DisclosureEnvironment {
    let controller: AppLifecycleController
    let hotKey: DisclosureHotKeyFake
    let presenter: DisclosurePresenterSpy

    static func make(host: SyntheticAXTextHost) -> DisclosureEnvironment {
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = DisclosureHotKeyFake()
        let presenter = DisclosurePresenterSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: DisclosurePermissionFake(),
            settingsOpener: DisclosureSettingsFake(),
            secureInputChecker: DisclosureSecureInputFake(),
            pasteboard: DisclosurePasteboardSpy(),
            gateway: gateway,
            targetMonitor: DisclosureMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return DisclosureEnvironment(
            controller: controller,
            hotKey: hotKey,
            presenter: presenter
        )
    }
}

@MainActor
private final class DisclosureHotKeyFake: HotKeySystemClient {
    private var callback: (() -> Void)?

    func registerExclusive(
        callback: @escaping () -> Void
    ) -> HotKeySystemRegistrationOutcome {
        self.callback = callback
        return .registered(HotKeyRegistrationToken(id: 1))
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        callback = nil
    }

    func press() {
        callback?()
    }
}

@MainActor
private final class DisclosurePresenterSpy: PreviewPresenting {
    var lastState: PreviewViewState?

    func show(_ state: PreviewViewState, anchorRect: CGRect?) {
        lastState = state
    }

    func update(_ state: PreviewViewState) {
        lastState = state
    }

    func dismiss() {
        lastState = nil
    }
}

@MainActor
private final class DisclosurePermissionFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class DisclosureSettingsFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class DisclosureSecureInputFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class DisclosurePasteboardSpy: PasteboardAccessing {
    func readStringAfterExplicitAction() -> String? {
        nil
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        true
    }
}

@MainActor
private final class DisclosureMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
