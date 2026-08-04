import Foundation
import XCTest

/// T-036: presentation latency instrumentation.
///
/// The 300ms budget in NFR-001 must be measured from the hot-key callback —
/// the first observable point inside the app — to the moment a visible shell
/// or explicit state is presented. These tests pin that measurement window
/// and prove the recorded sample carries timing only, never content.
@MainActor
final class PresentationLatencyInstrumentationTests: XCTestCase {
    func testLatencyIsMeasuredFromHotKeyCallbackToFirstPresentation() async {
        let env = LatencyEnvironment.make(host: .selectionFixture())
        env.clock.nextSamples = [1_000_000_000, 1_150_000_000]

        env.hotKey.press()
        await env.controller.captureWork?.value

        XCTAssertEqual(
            env.recorder.samples,
            [150_000_000],
            "elapsed time must span hot-key callback to first presentation"
        )
    }

    func testEachHotKeyPressRecordsExactlyOneSample() async {
        let env = LatencyEnvironment.make(host: .selectionFixture())
        env.clock.nextSamples = [0, 200_000_000]

        env.hotKey.press()
        await env.controller.captureWork?.value

        env.controller.handle(.confirmReplacement)
        await env.controller.applyWork?.value
        env.host.collapseSelectionAfterWrite()
        env.controller.handle(.restoreOriginal)
        await env.controller.recoverWork?.value
        await env.controller.cleanupWork?.value

        XCTAssertEqual(
            env.recorder.samples.count,
            1,
            "later state changes in the same session must not add samples"
        )
    }

    func testSecureInputRejectionIsAlsoMeasuredAsExplicitState() {
        let env = LatencyEnvironment.make(host: .selectionFixture())
        env.secureInput.isEnabled = true
        env.clock.nextSamples = [0, 50_000_000]

        env.hotKey.press()

        XCTAssertEqual(
            env.recorder.samples,
            [50_000_000],
            "a refusal is an explicit state and must be measured too"
        )
    }
}

// MARK: - Environment

@MainActor
private struct LatencyEnvironment {
    let host: SyntheticAXTextHost
    let controller: AppLifecycleController
    let hotKey: LatencyHotKeyClientFake
    let secureInput: LatencySecureInputCheckerFake
    let clock: LatencyClockFake
    let recorder: LatencyRecorderSpy
    let presenter: LatencyPresenterSpy

    static func make(host: SyntheticAXTextHost) -> LatencyEnvironment {
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = LatencyHotKeyClientFake()
        let secureInput = LatencySecureInputCheckerFake()
        let clock = LatencyClockFake()
        let recorder = LatencyRecorderSpy()
        let presenter = LatencyPresenterSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: LatencyPermissionCheckerFake(),
            settingsOpener: LatencySettingsOpenerFake(),
            secureInputChecker: secureInput,
            pasteboard: LatencyPasteboardSpy(),
            gateway: gateway,
            targetMonitor: LatencyTargetMonitorSpy(),
            presenter: presenter,
            clock: clock,
            latencyRecorder: recorder
        )
        _ = controller.start()
        return LatencyEnvironment(
            host: host,
            controller: controller,
            hotKey: hotKey,
            secureInput: secureInput,
            clock: clock,
            recorder: recorder,
            presenter: presenter
        )
    }
}

// MARK: - Fakes and spies

@MainActor
private final class LatencyClockFake:
    @preconcurrency MonotonicClockReading, @unchecked Sendable
{
    var nextSamples: [UInt64] = []
    private var index = 0

    func now() -> UInt64 {
        guard index < nextSamples.count else {
            return nextSamples.last ?? 0
        }
        defer { index += 1 }
        return nextSamples[index]
    }
}

@MainActor
private final class LatencyRecorderSpy: PresentationLatencyRecording {
    var samples: [UInt64] = []

    func recordPresentationLatency(nanoseconds: UInt64) {
        samples.append(nanoseconds)
    }
}

@MainActor
private final class LatencyHotKeyClientFake: HotKeySystemClient {
    enum Outcome {
        case registered
        case conflict
        case failed
    }

    var nextOutcome: Outcome = .registered
    private var callback: (() -> Void)?

    func registerExclusive(
        callback: @escaping () -> Void
    ) -> HotKeySystemRegistrationOutcome {
        switch nextOutcome {
        case .registered:
            self.callback = callback
            return .registered(HotKeyRegistrationToken(id: 1))
        case .conflict:
            return .conflict
        case .failed:
            return .failed
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
private final class LatencyPermissionCheckerFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class LatencySettingsOpenerFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class LatencySecureInputCheckerFake: SecureEventInputChecking {
    var isEnabled = false

    func isSecureEventInputEnabled() -> Bool {
        isEnabled
    }
}

@MainActor
private final class LatencyPasteboardSpy: PasteboardAccessing {
    func readStringAfterExplicitAction() -> String? {
        nil
    }

    func writeLocalStringAfterExplicitAction(
        _ text: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        true
    }
}

@MainActor
private final class LatencyPresenterSpy: PreviewPresenting {
    var lastState: PreviewViewState?

    func show(_ viewState: PreviewViewState, anchorRect: CGRect?) {
        lastState = viewState
    }

    func update(_ viewState: PreviewViewState) {
        lastState = viewState
    }

    func dismiss() {}
}

@MainActor
private final class LatencyTargetMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}

// MARK: - FR-001 / AC-002: hot-key registration failure must be explained

/// A conflicting or failed registration must surface an understandable state
/// instead of leaving the app silently unresponsive.
@MainActor
final class HotKeyRegistrationFailurePresentationTests: XCTestCase {
    private let mapper = PreviewPresentationMapper()

    func testConflictingRegistrationPresentsTheConflictState() {
        let env = LatencyEnvironment.make(host: .selectionFixture())
        env.hotKey.nextOutcome = .conflict

        let outcome = env.controller.start()

        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(
            env.presenter.lastState,
            mapper.viewState(for: .hotKeyConflict),
            "a conflicting hot key must be explained to the user"
        )
    }

    func testFailedRegistrationPresentsTheConflictState() {
        let env = LatencyEnvironment.make(host: .selectionFixture())
        env.hotKey.nextOutcome = .failed

        let outcome = env.controller.start()

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(env.presenter.lastState, mapper.viewState(for: .hotKeyConflict))
    }

    func testSuccessfulRegistrationPresentsNothing() {
        let env = LatencyEnvironment.make(host: .selectionFixture())

        _ = env.controller.start()

        XCTAssertNil(
            env.presenter.lastState,
            "a healthy registration must not show any panel"
        )
    }
}
