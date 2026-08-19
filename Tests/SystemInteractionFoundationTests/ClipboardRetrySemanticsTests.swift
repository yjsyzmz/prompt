import AppKit
import XCTest

/// Implementation Gate REVIEW（第二轮）MUST 3：复制失败面板上的「重试」必须
/// 重试那次失败的复制本身，而不是重新开一次会话。
///
/// NFR-007：失败必须给出安全的下一步。如果「重试」实际上重新捕获目标，
/// 用户想抢救的结果或原文就在这一步丢了——尤其是恢复失败后想复制原文的场景，
/// 那份原文是唯一还能拿回来的东西。
@MainActor
final class ClipboardRetrySemanticsTests: XCTestCase {
    private let mapper = PreviewPresentationMapper()

    func testRetryAfterFailedResultCopyCopiesTheResultAgain() async {
        let env = RetryEnvironment.make()
        env.pasteboard.writeSucceeds = false

        env.hotKey.press()
        await env.controller.captureWork?.value
        let readsBeforeRetry = env.host.contentReadCount
        env.controller.handle(.copyResult)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .clipboardWriteFailed).message
        )
        let attemptsAfterFirstCopy = env.pasteboard.attemptedValues.count

        env.pasteboard.writeSucceeds = true
        guard let retryAction = env.retryAction else {
            XCTFail("the failure panel must offer a retry")
            return
        }
        env.controller.handle(retryAction)

        XCTAssertEqual(
            env.pasteboard.attemptedValues.count,
            attemptsAfterFirstCopy + 1,
            "retry must attempt the copy again"
        )
        XCTAssertEqual(
            env.pasteboard.attemptedValues.last,
            env.expectedResultText,
            "retry must copy the result, not something else"
        )
        XCTAssertEqual(
            env.host.contentReadCount,
            readsBeforeRetry,
            "retry must not re-capture the target"
        )
    }

    func testRetryAfterFailedOriginalCopyCopiesTheOriginalAgain() async {
        let env = RetryEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        let expectedOriginal = env.expectedSourceText
        env.controller.handle(.confirmReplacement)
        await env.controller.applyWork?.value
        // Force the recovery to be refused so that copying the original becomes
        // the only remaining way to get the text back.
        env.host.editSegmentExternally("SYNTHETIC-001 外部改过的文字")
        env.controller.handle(.restoreOriginal)
        await env.controller.recoverWork?.value
        XCTAssertTrue(
            env.presenter.lastState?.buttons.contains {
                $0.action == .copyOriginal
            } ?? false,
            "this scenario requires the recovery-unavailable panel"
        )

        env.pasteboard.writeSucceeds = false
        env.controller.handle(.copyOriginal)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .clipboardWriteFailed).message
        )
        let attemptsAfterFirstCopy = env.pasteboard.attemptedValues.count

        env.pasteboard.writeSucceeds = true
        guard let retryAction = env.retryAction else {
            XCTFail("the failure panel must offer a retry")
            return
        }
        env.controller.handle(retryAction)

        XCTAssertEqual(
            env.pasteboard.attemptedValues.count,
            attemptsAfterFirstCopy + 1,
            "retry must attempt the copy again"
        )
        XCTAssertEqual(
            env.pasteboard.attemptedValues.last,
            expectedOriginal,
            "retry must copy the original, not the result"
        )
    }

    func testSuccessfulRetryLeavesTheFailurePanel() async {
        let env = RetryEnvironment.make()
        env.pasteboard.writeSucceeds = false

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.copyResult)
        env.pasteboard.writeSucceeds = true
        guard let retryAction = env.retryAction else {
            XCTFail("the failure panel must offer a retry")
            return
        }
        env.controller.handle(retryAction)

        XCTAssertNotEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .clipboardWriteFailed).message,
            "a successful retry must not keep reporting a failure"
        )
    }

    func testRepeatedFailureKeepsOfferingTheRetry() async {
        let env = RetryEnvironment.make()
        env.pasteboard.writeSucceeds = false

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.copyResult)
        guard let firstRetry = env.retryAction else {
            XCTFail("the failure panel must offer a retry")
            return
        }
        env.controller.handle(firstRetry)

        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .clipboardWriteFailed).message
        )
        XCTAssertNotNil(
            env.retryAction,
            "a still-failing copy must keep the retry available"
        )
    }
}

// MARK: - Environment

@MainActor
private struct RetryEnvironment {
    let controller: AppLifecycleController
    let host: SyntheticAXTextHost
    let hotKey: RetryHotKeyFake
    let presenter: RetryPresenterSpy
    let pasteboard: RetryPasteboardSpy

    /// The retry affordance the failure panel currently offers, whatever its
    /// concrete action turns out to be.
    var retryAction: PreviewUserAction? {
        presenter.lastState?.buttons
            .first { $0.action != .close && $0.action != .cancel }?
            .action
    }

    var expectedSourceText: String {
        SyntheticAXTextHost.selectionFixture().selectedSegment
    }

    var expectedResultText: String {
        DeterministicTransformer().transform(SourceText(expectedSourceText)).value
    }

    static func make() -> RetryEnvironment {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = RetryHotKeyFake()
        let presenter = RetryPresenterSpy()
        let pasteboard = RetryPasteboardSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: RetryPermissionFake(),
            settingsOpener: RetrySettingsFake(),
            secureInputChecker: RetrySecureInputFake(),
            pasteboard: pasteboard,
            gateway: gateway,
            targetMonitor: RetryMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return RetryEnvironment(
            controller: controller,
            host: host,
            hotKey: hotKey,
            presenter: presenter,
            pasteboard: pasteboard
        )
    }
}

@MainActor
private final class RetryHotKeyFake: HotKeySystemClient {
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
private final class RetryPresenterSpy: PreviewPresenting {
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
private final class RetryPermissionFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class RetrySettingsFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class RetrySecureInputFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class RetryPasteboardSpy: PasteboardAccessing {
    var writeSucceeds = true
    private(set) var attemptedValues: [String] = []

    func readStringAfterExplicitAction() -> String? {
        "SYNTHETIC-001 剪贴板文字"
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        attemptedValues.append(value)
        return writeSucceeds
    }
}

@MainActor
private final class RetryMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
