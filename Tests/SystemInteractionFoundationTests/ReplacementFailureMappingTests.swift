import AppKit
import XCTest

/// Implementation Gate REVIEW（第二轮）MUST 2：确认替换被授权校验拒绝时，
/// 面板必须解释真实的拒绝原因，不能一律说成「未能安全替换原文」。
///
/// NFR-007：失败必须给出可理解的说明与安全的下一步。把「目标已经变化、
/// 从未发生写入」和「确实尝试了写入但失败」混为一谈，会让用户以为目标
/// 内容可能已被改动，而事实上一个 setter 都没调用过。
@MainActor
final class ReplacementFailureMappingTests: XCTestCase {
    private let mapper = PreviewPresentationMapper()

    // MARK: - 从未发生写入的拒绝，不能呈现为写入失败

    func testWindowChangeBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.switchWindow()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(
            env.host.setterAttemptCount,
            0,
            "A3 rejects before any setter runs, so nothing was written"
        )
        XCTAssertNotEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .writeFailed).message,
            "a pre-write rejection must not be reported as a failed write"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message
        )
    }

    func testElementInvalidationBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.invalidateElement()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "A4 identity mismatch is a stale target, not a write failure"
        )
    }

    func testApplicationTerminationBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.terminateApplication()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "A1 rejects a terminated application before any write"
        )
    }

    func testFocusMovedToAnotherApplicationIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.moveFocusToDifferentApplication()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "A2 rejects a changed frontmost application before any write"
        )
    }

    func testExternalContentEditBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.editSegmentExternally("SYNTHETIC-001 外部改过的文字")
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(
            env.host.setterAttemptCount,
            0,
            "B1 compares content before the setter, so nothing was written"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "a source change is a stale target, not a write failure"
        )
    }

    // MARK: - 真正尝试过写入的失败仍必须呈现为写入失败

    func testForcedSetterFailureRemainsAWriteFailure() async {
        let env = MappingEnvironment.make()
        env.host.failNextSetterAttempts(100)

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)

        XCTAssertGreaterThan(
            env.host.setterAttemptCount,
            0,
            "this path did attempt a write"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .writeFailed).message,
            "an attempted-but-failed write keeps the writeFailed explanation"
        )
    }

    // MARK: - 两类失败必须在文案上可区分

    func testStaleAndWriteFailureCopyAreDistinguishable() {
        XCTAssertNotEqual(
            mapper.viewState(for: .staleTarget).message,
            mapper.viewState(for: .writeFailed).message
        )
    }

    // MARK: - 拒绝状态一律不得展示内容，且必须留有安全出口

    func testRejectionStatesDiscloseNoContentAndKeepCopyAvailable() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.switchWindow()
        env.controller.handle(.confirmReplacement)

        guard let state = env.presenter.lastState else {
            XCTFail("a rejection must present a state")
            return
        }
        XCTAssertNil(state.sourceText, "FR-013: a refusal state discloses no content")
        XCTAssertNil(state.resultText)
        XCTAssertTrue(
            state.buttons.contains { $0.action == .copyResult && $0.isEnabled },
            "NFR-007 requires a safe next step: the result stays copyable"
        )
        XCTAssertFalse(
            state.canConfirmReplacement,
            "a rejected target must not offer another confirmation"
        )
    }
}

// MARK: - Environment

@MainActor
private struct MappingEnvironment {
    let controller: AppLifecycleController
    let host: SyntheticAXTextHost
    let hotKey: MappingHotKeyFake
    let presenter: MappingPresenterSpy

    static func make() -> MappingEnvironment {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = MappingHotKeyFake()
        let presenter = MappingPresenterSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: MappingPermissionFake(),
            settingsOpener: MappingSettingsFake(),
            secureInputChecker: MappingSecureInputFake(),
            pasteboard: MappingPasteboardSpy(),
            gateway: gateway,
            targetMonitor: MappingMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return MappingEnvironment(
            controller: controller,
            host: host,
            hotKey: hotKey,
            presenter: presenter
        )
    }
}

@MainActor
private final class MappingHotKeyFake: HotKeySystemClient {
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
private final class MappingPresenterSpy: PreviewPresenting {
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
private final class MappingPermissionFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class MappingSettingsFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class MappingSecureInputFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class MappingPasteboardSpy: PasteboardAccessing {
    func readStringAfterExplicitAction() -> String? {
        "SYNTHETIC-001 剪贴板文字"
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        true
    }
}

@MainActor
private final class MappingMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
