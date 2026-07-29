import Foundation
import XCTest

/// T-030: synthetic end-to-end integration tests.
///
/// Drives the full production assembly — hot key, permission flow, capture
/// through `AccessibilityGateway`, preview presentation, authoritative
/// single write, and recovery — against the T-029 synthetic AX host and
/// spies. Every path asserts the setter count is zero before an explicit
/// confirmation.
@MainActor
final class EndToEndIntegrationTests: XCTestCase {
    private let mapper = PreviewPresentationMapper()
    private let transformer = DeterministicTransformer()

    // MARK: - Happy path

    func testDirectFlowReplacesOnceAndRestoresOriginal() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        let originalFullText = env.host.fullText
        let originalSegment = env.host.selectedSegment
        let transformed = transformer.transform(SourceText(originalSegment))

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        // Finding 1: an actionable preview also discloses the source text and
        // the deterministic result, so compare the copy and buttons only.
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .ready).message
        )
        XCTAssertEqual(
            env.presenter.lastState?.buttons,
            mapper.viewState(for: .ready).buttons
        )
        XCTAssertNotNil(env.presenter.lastState?.sourceText)
        XCTAssertNotNil(env.presenter.lastState?.resultText)
        XCTAssertEqual(env.monitor.startCount, 1)

        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 1)
        XCTAssertEqual(env.host.selectedSegment, transformed.value)
        XCTAssertEqual(
            env.host.fullText,
            originalFullText.replacingOccurrences(
                of: originalSegment,
                with: transformed.value
            )
        )
        guard let recoverableState = env.presenter.lastState else {
            XCTFail("recoverable state must be presented after confirmation")
            return
        }
        XCTAssertTrue(
            recoverableState.buttons.contains {
                $0.action == .restoreOriginal && $0.isEnabled
            },
            "recoverable state must offer an enabled restore action"
        )
        XCTAssertFalse(recoverableState.message.isEmpty)

        env.host.collapseSelectionAfterWrite()
        env.controller.handle(.restoreOriginal)
        await env.controller.cleanupWork?.value

        XCTAssertEqual(env.host.setterAttemptCount, 2)
        XCTAssertEqual(env.host.fullText, originalFullText)
        XCTAssertEqual(env.presenter.dismissCount, 1)
        XCTAssertEqual(env.monitor.stopCount, 1)

        let presentedBefore = env.presenter.presentedStateCount
        await env.gateway.receive(env.monitor.lastEnvelope!)
        XCTAssertEqual(
            env.presenter.presentedStateCount,
            presentedBefore,
            "monitor callbacks after session end must be ignored"
        )
    }

    // MARK: - Cancel, copy, clipboard hygiene

    func testCancelPerformsNoWriteAndNoClipboardAccess() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        let originalFullText = env.host.fullText

        env.hotKey.press()
        await env.controller.captureWork?.value
        XCTAssertEqual(env.host.setterAttemptCount, 0)

        env.controller.handle(.cancel)
        await env.controller.cleanupWork?.value

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(env.host.fullText, originalFullText)
        XCTAssertEqual(env.pasteboard.writeCount, 0)
        XCTAssertEqual(env.pasteboard.readCount, 0)
        XCTAssertEqual(env.presenter.dismissCount, 1)
        XCTAssertEqual(env.monitor.stopCount, 1)
    }

    func testCopyResultWritesClipboardExactlyOnce() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        let transformed = transformer.transform(
            SourceText(env.host.selectedSegment)
        )

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.copyResult)

        XCTAssertEqual(env.pasteboard.writeCount, 1)
        XCTAssertEqual(env.pasteboard.writtenValues.last, transformed.value)
        XCTAssertEqual(env.pasteboard.writtenPrivacies.last, .currentHostOnly)
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }

    // MARK: - Refusal paths

    func testSecureInputRejectsWithoutAnyContentRead() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        env.secureInput.isEnabled = true

        env.hotKey.press()

        XCTAssertNil(env.controller.captureWork)
        XCTAssertEqual(env.presenter.lastState, mapper.viewState(for: .secureInput))
        XCTAssertEqual(env.host.contentReadCount, 0)
        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(env.pasteboard.readCount, 0)
    }

    func testMissingPermissionPresentsPermissionRequiredWithoutReads() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        env.permission.status = .notAuthorized

        env.hotKey.press()

        XCTAssertNil(env.controller.captureWork)
        XCTAssertEqual(
            env.presenter.lastState,
            mapper.viewState(for: .permissionRequired)
        )
        XCTAssertEqual(env.host.contentReadCount, 0)
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }

    func testFailedPermissionRecheckExplainsThatPermissionIsStillMissing() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        env.permission.status = .notAuthorized

        env.hotKey.press()
        let presentedBeforeRecheck = env.presenter.presentedStateCount

        env.controller.handle(.recheckPermission)

        XCTAssertEqual(env.presenter.presentedStateCount, presentedBeforeRecheck + 1)
        XCTAssertEqual(
            env.presenter.lastState?.buttons,
            mapper.viewState(for: .permissionRequired).buttons
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            "仍未检测到辅助功能权限。请在系统设置中启用本应用后，关闭并重新打开应用，再重新检测。"
        )
        XCTAssertEqual(env.host.contentReadCount, 0)
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }

    func testEmptyTargetPresentsEmptyOrUnsupported() async {
        let env = IntegrationEnvironment.make(host: .emptyFixture())

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertEqual(
            env.presenter.lastState,
            mapper.viewState(for: .emptyOrUnsupported)
        )
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }

    // MARK: - Stale target and write failure

    func testStaleTargetEventDisablesConfirmAndValidationBlocksWrite() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        let originalFullText = env.host.fullText

        env.hotKey.press()
        await env.controller.captureWork?.value
        XCTAssertEqual(env.host.setterAttemptCount, 0)

        env.host.switchWindow()
        await env.gateway.receive(env.monitor.lastEnvelope!)

        guard let staleState = env.presenter.lastState else {
            XCTFail("stale target must be presented")
            return
        }
        XCTAssertEqual(staleState, mapper.viewState(for: .staleTarget))
        XCTAssertFalse(staleState.canConfirmReplacement)

        // The monitor event only disables the button; the authoritative
        // validation remains the actual write gate if a confirm still races in.
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(env.host.fullText, originalFullText)
        XCTAssertEqual(
            env.presenter.lastState,
            mapper.viewState(for: .writeFailed)
        )
    }

    func testForcedSetterFailurePresentsWriteFailedAndKeepsOriginal() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        let originalFullText = env.host.fullText
        let transformed = transformer.transform(
            SourceText(env.host.selectedSegment)
        )

        env.hotKey.press()
        await env.controller.captureWork?.value
        XCTAssertEqual(env.host.setterAttemptCount, 0)

        env.host.failNextSetterAttempts(1)
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 1)
        XCTAssertEqual(env.host.fullText, originalFullText)
        XCTAssertEqual(
            env.presenter.lastState,
            mapper.viewState(for: .writeFailed)
        )

        env.controller.handle(.copyResult)
        XCTAssertEqual(env.pasteboard.writeCount, 1)
        XCTAssertEqual(env.pasteboard.writtenValues.last, transformed.value)
    }

    func testRecoveryUnavailableWhenResultChangedAfterApply() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        let originalSegment = env.host.selectedSegment

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)
        XCTAssertEqual(env.host.setterAttemptCount, 1)

        env.host.editSegmentExternally("SYNTHETIC-001 被外部修改的结果")
        env.controller.handle(.restoreOriginal)

        XCTAssertEqual(
            env.presenter.lastState?.message,
            "目标文字已经变化，无法直接恢复。"
        )
        XCTAssertEqual(
            env.presenter.lastState?.buttons,
            mapper.viewState(for: .recoveryUnavailable).buttons
        )
        XCTAssertEqual(
            env.host.setterAttemptCount,
            1,
            "a failed recovery validation must not write again"
        )

        env.controller.handle(.copyOriginal)
        XCTAssertEqual(env.pasteboard.writeCount, 1)
        XCTAssertEqual(env.pasteboard.writtenValues.last, originalSegment)

        env.controller.handle(.close)
        await env.controller.cleanupWork?.value
        XCTAssertEqual(env.presenter.dismissCount, 1)
    }

    // MARK: - Session replacement and clipboard input

    func testNewSessionReplacesOldAndIgnoresStaleCallbacks() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())

        env.hotKey.press()
        await env.controller.captureWork?.value
        guard let firstEnvelope = env.monitor.lastEnvelope else {
            XCTFail("first session must start monitoring")
            return
        }

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertEqual(env.monitor.startCount, 2)
        XCTAssertGreaterThanOrEqual(env.monitor.stopCount, 1)
        XCTAssertGreaterThanOrEqual(env.presenter.dismissCount, 1)
        // Finding 1: an actionable preview also discloses the source text and
        // the deterministic result, so compare the copy and buttons only.
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .ready).message
        )
        XCTAssertEqual(
            env.presenter.lastState?.buttons,
            mapper.viewState(for: .ready).buttons
        )
        XCTAssertNotNil(env.presenter.lastState?.sourceText)
        XCTAssertNotNil(env.presenter.lastState?.resultText)
        XCTAssertEqual(env.host.setterAttemptCount, 0)

        let presentedBefore = env.presenter.presentedStateCount
        await env.gateway.receive(firstEnvelope)
        XCTAssertEqual(
            env.presenter.presentedStateCount,
            presentedBefore,
            "callbacks addressed to the replaced session must be ignored"
        )
    }

    func testClipboardInputSessionForbidsDirectReplacement() async {
        let env = IntegrationEnvironment.make(host: .selectionFixture())
        env.pasteboard.stringToRead = "SYNTHETIC-001 剪贴板输入文字"

        env.controller.handle(.useClipboard)

        guard let readyState = env.presenter.lastState else {
            XCTFail("clipboard session must present a preview")
            return
        }
        XCTAssertFalse(
            readyState.buttons.contains { $0.action == .confirmReplacement },
            "clipboard input must never offer direct replacement"
        )
        XCTAssertEqual(env.pasteboard.readCount, 1)

        env.controller.handle(.confirmReplacement)
        XCTAssertEqual(env.host.setterAttemptCount, 0)
    }
}

// MARK: - Environment

@MainActor
private struct IntegrationEnvironment {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let controller: AppLifecycleController
    let hotKey: IntegrationHotKeyClientFake
    let permission: IntegrationPermissionCheckerFake
    let secureInput: IntegrationSecureInputCheckerFake
    let pasteboard: IntegrationPasteboardSpy
    let presenter: IntegrationPresenterSpy
    let monitor: IntegrationTargetMonitorSpy

    static func make(host: SyntheticAXTextHost) -> IntegrationEnvironment {
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = IntegrationHotKeyClientFake()
        let permission = IntegrationPermissionCheckerFake()
        let secureInput = IntegrationSecureInputCheckerFake()
        let pasteboard = IntegrationPasteboardSpy()
        let presenter = IntegrationPresenterSpy()
        let monitor = IntegrationTargetMonitorSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: permission,
            settingsOpener: IntegrationSettingsOpenerFake(),
            secureInputChecker: secureInput,
            pasteboard: pasteboard,
            gateway: gateway,
            targetMonitor: monitor,
            presenter: presenter
        )
        _ = controller.start()
        return IntegrationEnvironment(
            host: host,
            gateway: gateway,
            controller: controller,
            hotKey: hotKey,
            permission: permission,
            secureInput: secureInput,
            pasteboard: pasteboard,
            presenter: presenter,
            monitor: monitor
        )
    }
}

// MARK: - Fakes and spies

@MainActor
private final class IntegrationHotKeyClientFake: HotKeySystemClient {
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
private final class IntegrationPermissionCheckerFake: AccessibilityPermissionChecking {
    var status: AccessibilityPermissionStatus = .authorized

    func currentStatus() -> AccessibilityPermissionStatus {
        status
    }
}

@MainActor
private final class IntegrationSettingsOpenerFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class IntegrationSecureInputCheckerFake: SecureEventInputChecking {
    var isEnabled = false

    func isSecureEventInputEnabled() -> Bool {
        isEnabled
    }
}

@MainActor
private final class IntegrationPasteboardSpy: PasteboardAccessing {
    var stringToRead: String?
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var writtenValues: [String] = []
    private(set) var writtenPrivacies: [PasteboardWritePrivacy] = []

    func readStringAfterExplicitAction() -> String? {
        readCount += 1
        return stringToRead
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        writeCount += 1
        writtenValues.append(value)
        writtenPrivacies.append(privacy)
        return true
    }
}

@MainActor
private final class IntegrationPresenterSpy: PreviewPresenting {
    private(set) var presentedStates: [PreviewViewState] = []
    private(set) var dismissCount = 0

    var lastState: PreviewViewState? {
        presentedStates.last
    }

    var presentedStateCount: Int {
        presentedStates.count
    }

    func show(_ state: PreviewViewState, anchorRect: CGRect?) {
        presentedStates.append(state)
    }

    func update(_ state: PreviewViewState) {
        presentedStates.append(state)
    }

    func dismiss() {
        dismissCount += 1
    }
}

@MainActor
private final class IntegrationTargetMonitorSpy: TargetChangeMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastEnvelope: AXMonitorCallbackEnvelope?

    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {
        startCount += 1
        lastEnvelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
    }

    func stopMonitoring() {
        stopCount += 1
    }
}
