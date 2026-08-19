import AppKit
import XCTest

/// Implementation Gate REVIEW Finding 6：显式复制失败、设置深链回退与快捷键
/// 冲突都必须给出可理解说明与安全下一步（NFR-007、FR-002、AC-002、AC-003）。
@MainActor
final class FailureRecoveryGuidanceTests: XCTestCase {
    private let mapper = PreviewPresentationMapper()

    // MARK: - 剪贴板写入失败

    func testFailedCopyResultIsSurfacedInsteadOfBeingSilent() async {
        let env = GuidanceEnvironment.make()
        env.pasteboard.writeSucceeds = false

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.copyResult)

        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .clipboardWriteFailed).message,
            "a failed explicit copy must be reported to the user"
        )
        XCTAssertTrue(
            env.presenter.lastState?.buttons.contains { $0.action == .retryCopy } ?? false
        )
    }

    func testSuccessfulCopyResultKeepsTheReadyState() async {
        let env = GuidanceEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.copyResult)

        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .ready).message
        )
    }

    func testFailedCopyOriginalIsSurfaced() async {
        let env = GuidanceEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)
        await env.controller.applyWork?.value
        env.host.replaceFullTextForTesting("SYNTHETIC-001 被外部改动的文字")
        env.controller.handle(.restoreOriginal)
        await env.controller.recoverWork?.value
        env.pasteboard.writeSucceeds = false
        env.controller.handle(.copyOriginal)

        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .clipboardWriteFailed).message
        )
    }

    // MARK: - 剪贴板读取失败与空内容必须区分

    func testEmptyClipboardAndUnreadableClipboardAreDistinguished() async {
        let emptyEnv = GuidanceEnvironment.make()
        emptyEnv.pasteboard.readValue = ""
        emptyEnv.hotKey.press()
        await emptyEnv.controller.captureWork?.value
        emptyEnv.controller.handle(.useClipboard)
        let emptyMessage = emptyEnv.presenter.lastState?.message

        let failedEnv = GuidanceEnvironment.make()
        failedEnv.pasteboard.readValue = nil
        failedEnv.hotKey.press()
        await failedEnv.controller.captureWork?.value
        failedEnv.controller.handle(.useClipboard)
        let failedMessage = failedEnv.presenter.lastState?.message

        XCTAssertEqual(
            emptyMessage,
            mapper.viewState(for: .emptyOrUnsupported).message
        )
        XCTAssertEqual(
            failedMessage,
            mapper.viewState(for: .clipboardReadFailed).message
        )
        XCTAssertNotEqual(
            emptyMessage,
            failedMessage,
            "an unreadable clipboard must not be reported as empty content"
        )
    }

    // MARK: - 设置深链回退

    func testPermissionStateAlwaysCarriesManualNavigationGuidance() {
        let state = mapper.viewState(for: .permissionRequired)

        XCTAssertTrue(
            state.message.contains("隐私与安全性"),
            "the copy must name the settings location the user can navigate to"
        )
        XCTAssertTrue(state.message.contains("辅助功能"))
    }

    func testDeepLinkFallbackPresentsManualNavigationStep() async {
        let env = GuidanceEnvironment.make(permission: .notAuthorized)
        env.settings.accessibilityDeepLinkSucceeds = false

        env.hotKey.press()
        env.controller.handle(.openSettings)

        guard let message = env.presenter.lastState?.message else {
            XCTFail("a fallback state must be presented")
            return
        }
        XCTAssertTrue(
            message.contains("隐私与安全性"),
            "the fallback must tell the user where to navigate manually"
        )
        XCTAssertTrue(
            env.presenter.lastState?.buttons.contains {
                $0.action == .recheckPermission
            } ?? false
        )
    }

    // MARK: - 快捷键冲突的重新注册

    func testHotKeyConflictOffersRegistrationRetry() {
        let state = mapper.viewState(for: .hotKeyConflict)

        XCTAssertTrue(
            state.buttons.contains { $0.action == .retryRegistration && $0.isEnabled },
            "AC-002 requires a safe next step that can clear the conflict"
        )
    }

    func testRetryRegistrationReRegistersTheHotKey() {
        let env = GuidanceEnvironment.make()
        env.hotKey.nextOutcome = .conflict
        _ = env.controller.start()
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .hotKeyConflict).message
        )

        env.hotKey.nextOutcome = .registered
        env.controller.handle(.retryRegistration)

        XCTAssertEqual(
            env.hotKey.registerAttempts,
            3,
            "retrying must attempt registration again (make + conflict + retry)"
        )
        XCTAssertNil(
            env.presenter.lastState,
            "a successful re-registration must dismiss the conflict panel"
        )
    }
}

// MARK: - Environment

@MainActor
private struct GuidanceEnvironment {
    let controller: AppLifecycleController
    let host: SyntheticAXTextHost
    let hotKey: GuidanceHotKeyFake
    let presenter: GuidancePresenterSpy
    let pasteboard: GuidancePasteboardSpy
    let settings: GuidanceSettingsFake

    static func make(
        permission: AccessibilityPermissionStatus = .authorized
    ) -> GuidanceEnvironment {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = GuidanceHotKeyFake()
        let presenter = GuidancePresenterSpy()
        let pasteboard = GuidancePasteboardSpy()
        let settings = GuidanceSettingsFake()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: GuidancePermissionFake(status: permission),
            settingsOpener: settings,
            secureInputChecker: GuidanceSecureInputFake(),
            pasteboard: pasteboard,
            gateway: gateway,
            targetMonitor: GuidanceMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return GuidanceEnvironment(
            controller: controller,
            host: host,
            hotKey: hotKey,
            presenter: presenter,
            pasteboard: pasteboard,
            settings: settings
        )
    }
}

@MainActor
private final class GuidanceHotKeyFake: HotKeySystemClient {
    enum Outcome {
        case registered
        case conflict
    }

    var nextOutcome: Outcome = .registered
    private(set) var registerAttempts = 0
    private var callback: (() -> Void)?

    func registerExclusive(
        callback: @escaping () -> Void
    ) -> HotKeySystemRegistrationOutcome {
        registerAttempts += 1
        switch nextOutcome {
        case .registered:
            self.callback = callback
            return .registered(HotKeyRegistrationToken(id: 1))
        case .conflict:
            return .conflict
        }
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        callback = nil
    }

    func press() {
        callback?()
    }
}

@MainActor
private final class GuidancePresenterSpy: PreviewPresenting {
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
private final class GuidancePermissionFake: AccessibilityPermissionChecking {
    private let status: AccessibilityPermissionStatus

    init(status: AccessibilityPermissionStatus) {
        self.status = status
    }

    func currentStatus() -> AccessibilityPermissionStatus {
        status
    }
}

@MainActor
private final class GuidanceSettingsFake: AccessibilitySettingsOpening {
    var accessibilityDeepLinkSucceeds = true
    var privacyPaneSucceeds = true

    func openAccessibilitySettings() -> Bool {
        accessibilityDeepLinkSucceeds
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        privacyPaneSucceeds
    }
}

@MainActor
private final class GuidanceSecureInputFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class GuidancePasteboardSpy: PasteboardAccessing {
    var writeSucceeds = true
    var readValue: String? = "SYNTHETIC-001 剪贴板文字"

    func readStringAfterExplicitAction() -> String? {
        readValue
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        writeSucceeds
    }
}

@MainActor
private final class GuidanceMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
