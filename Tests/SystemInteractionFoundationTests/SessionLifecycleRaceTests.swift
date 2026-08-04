import AppKit
import XCTest

/// Implementation Gate REVIEW Finding 4：过期的异步捕获不得遗留 AX handle 或
/// 内容引用；安全输入下的重复触发必须先结束旧会话（FR-013、AC-014）。
@MainActor
final class SessionLifecycleRaceTests: XCTestCase {
    /// 取消发生在 capture 仍在进行时：捕获结果作废，但 handle 必须释放。
    func testCancelDuringSuspendedCaptureReleasesTargetHandle() async {
        let env = RaceEnvironment.make()

        env.hotKey.press()
        // The capture task is created but has not resumed yet; cancelling here
        // makes the pending capture stale.
        env.controller.handle(.cancel)
        await env.controller.captureWork?.value
        await env.controller.cleanupWork?.value

        let retained = await env.gateway.retainedTargetCount()
        XCTAssertEqual(
            retained,
            0,
            "a stale capture must release the AX handle it created"
        )
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }

    /// 新会话替换旧会话时，旧捕获的 handle 也必须释放。
    func testNewSessionDuringSuspendedCaptureReleasesFirstHandle() async {
        let env = RaceEnvironment.make()

        env.hotKey.press()
        env.hotKey.press()
        await env.controller.captureWork?.value
        await env.controller.cleanupWork?.value

        let retained = await env.gateway.retainedTargetCount()
        XCTAssertLessThanOrEqual(
            retained,
            1,
            "only the newest session may retain a handle"
        )
    }

    // 说明：`activateMonitoring` 之后、`startMonitoring` 之前的竞态窗口无法在
    // 合成层可靠触发（该窗口内没有可注入的挂起点），因此不为它编写会被"恒真"
    // 通过的断言。该路径的释放逻辑与上面两条竞态共用
    // `releaseStaleCapture`／`clearActiveTargetState`，由代码审查覆盖。

    /// 安全输入下再次触发必须先结束已有会话，并且不读取任何内容。
    func testSecureInputTriggerEndsExistingSession() async {
        let env = RaceEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        XCTAssertTrue(env.presenter.lastState?.canConfirmReplacement ?? false)
        let readsAfterFirstCapture = env.host.contentReadCount

        env.secureInput.isEnabled = true
        env.hotKey.press()
        await env.controller.cleanupWork?.value

        XCTAssertEqual(
            env.presenter.lastState?.message,
            PreviewPresentationMapper().viewState(for: .secureInput).message
        )
        XCTAssertNil(
            env.presenter.lastState?.sourceText,
            "the secure-input state must not keep disclosing earlier content"
        )
        XCTAssertEqual(
            env.host.contentReadCount,
            readsAfterFirstCapture,
            "secure input must not read any content"
        )
        let retained = await env.gateway.retainedTargetCount()
        XCTAssertEqual(
            retained,
            0,
            "the previous session's handle must be released"
        )
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }

    /// 安全输入拒绝后，恢复动作不能再作用于旧目标。
    func testSecureInputTriggerClearsRecoverableSession() async {
        let env = RaceEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)
        await env.controller.applyWork?.value
        let settersAfterReplacement = env.host.setterAttemptCount

        env.secureInput.isEnabled = true
        env.hotKey.press()
        await env.controller.cleanupWork?.value
        env.controller.handle(.restoreOriginal)
        await env.controller.recoverWork?.value

        XCTAssertEqual(
            env.host.setterAttemptCount,
            settersAfterReplacement,
            "restore must not write after the session was ended by secure input"
        )
    }
}

// MARK: - Environment

@MainActor
private struct RaceEnvironment {
    let controller: AppLifecycleController
    let gateway: AccessibilityGateway
    let host: SyntheticAXTextHost
    let hotKey: RaceHotKeyFake
    let presenter: RacePresenterSpy
    let secureInput: RaceSecureInputFake

    static func make() -> RaceEnvironment {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = RaceHotKeyFake()
        let presenter = RacePresenterSpy()
        let secureInput = RaceSecureInputFake()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: RacePermissionFake(),
            settingsOpener: RaceSettingsFake(),
            secureInputChecker: secureInput,
            pasteboard: RacePasteboardSpy(),
            gateway: gateway,
            targetMonitor: RaceMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return RaceEnvironment(
            controller: controller,
            gateway: gateway,
            host: host,
            hotKey: hotKey,
            presenter: presenter,
            secureInput: secureInput
        )
    }
}

@MainActor
private final class RaceHotKeyFake: HotKeySystemClient {
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
private final class RacePresenterSpy: PreviewPresenting {
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
private final class RacePermissionFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class RaceSettingsFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class RaceSecureInputFake: SecureEventInputChecking {
    var isEnabled = false

    func isSecureEventInputEnabled() -> Bool {
        isEnabled
    }
}

@MainActor
private final class RacePasteboardSpy: PasteboardAccessing {
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
private final class RaceMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
