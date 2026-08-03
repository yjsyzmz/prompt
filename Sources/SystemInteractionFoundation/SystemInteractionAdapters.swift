import Carbon.HIToolbox
import Dispatch
import os

struct HotKeyRegistrationToken: Equatable, Sendable {
    let id: UInt32
}

enum HotKeySystemRegistrationOutcome: Equatable, Sendable {
    case registered(HotKeyRegistrationToken)
    case conflict
    case failed
}

enum GlobalHotKeyRegistrationOutcome: Equatable, Sendable {
    case registered
    case conflict
    case failed
}

@MainActor
protocol HotKeySystemClient: AnyObject {
    func registerExclusive(
        callback: @escaping () -> Void
    ) -> HotKeySystemRegistrationOutcome

    func unregister(_ token: HotKeyRegistrationToken)
}

@MainActor
final class GlobalHotKeyRegistrar {
    private let systemClient: any HotKeySystemClient
    private var activeToken: HotKeyRegistrationToken?

    init(systemClient: any HotKeySystemClient) {
        self.systemClient = systemClient
    }

    func register(onPress: @escaping () -> Void) -> GlobalHotKeyRegistrationOutcome {
        switch systemClient.registerExclusive(callback: onPress) {
        case .registered(let token):
            activeToken = token
            return .registered
        case .conflict:
            return .conflict
        case .failed:
            return .failed
        }
    }

    func unregister() {
        guard let activeToken else {
            return
        }

        self.activeToken = nil
        systemClient.unregister(activeToken)
    }
}

@MainActor
final class HIToolboxHotKeySystemClient: HotKeySystemClient {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let hotKeyID: EventHotKeyID

    private var callback: (() -> Void)?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeToken: HotKeyRegistrationToken?

    init(
        keyCode: UInt32,
        modifiers: UInt32,
        signature: OSType,
        identifier: UInt32
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        hotKeyID = EventHotKeyID(signature: signature, id: identifier)
    }

    func registerExclusive(
        callback: @escaping () -> Void
    ) -> HotKeySystemRegistrationOutcome {
        guard hotKeyRef == nil, eventHandlerRef == nil else {
            return .failed
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            systemInteractionHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard handlerStatus == noErr, let installedHandler else {
            return .failed
        }

        var registeredHotKey: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &registeredHotKey
        )

        guard registrationStatus == noErr, let registeredHotKey else {
            RemoveEventHandler(installedHandler)
            if registrationStatus == eventHotKeyExistsErr {
                return .conflict
            }
            return .failed
        }

        let token = HotKeyRegistrationToken(id: hotKeyID.id)
        self.callback = callback
        eventHandlerRef = installedHandler
        hotKeyRef = registeredHotKey
        activeToken = token
        return .registered(token)
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        guard token == activeToken else {
            return
        }

        activeToken = nil
        callback = nil

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    fileprivate func receiveHotKeyPressed() {
        callback?()
    }
}

private func systemInteractionHotKeyHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let client = Unmanaged<HIToolboxHotKeySystemClient>
        .fromOpaque(userData)
        .takeUnretainedValue()
    MainActor.assumeIsolated {
        client.receiveHotKeyPressed()
    }
    return noErr
}

@MainActor
protocol SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool
}

enum SecureInputDecision: Equatable, Sendable {
    case allowed
    case blocked
}

@MainActor
struct HIToolboxSecureEventInputChecker: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }
}

@MainActor
struct SecureInputGuard {
    private let checker: any SecureEventInputChecking

    init(checker: any SecureEventInputChecking) {
        self.checker = checker
    }

    @discardableResult
    func performIfContentReadAllowed(
        _ contentRead: () -> Void
    ) -> SecureInputDecision {
        guard !checker.isSecureEventInputEnabled() else {
            return .blocked
        }

        contentRead()
        return .allowed
    }
}

protocol MonotonicClockReading {
    func now() -> UInt64
}

struct SystemMonotonicClock: MonotonicClockReading {
    func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

struct CapabilityProbeClock {
    private let clock: any MonotonicClockReading

    init(clock: any MonotonicClockReading) {
        self.clock = clock
    }

    func sampleAtHotKeyCallback() -> UInt64 {
        clock.now()
    }
}

/// T-036 observability: the 300ms budget is measured from the hot-key
/// callback to the first presented state. Only elapsed time is recorded —
/// never captured text — so this stays inside the FR-013 privacy boundary.
@MainActor
protocol PresentationLatencyRecording {
    func recordPresentationLatency(nanoseconds: UInt64)
}

@MainActor
struct OSLogPresentationLatencyRecorder: PresentationLatencyRecording {
    private let log = Logger(
        subsystem: "com.systeminteractionfoundation.verification",
        category: "presentation-latency"
    )

    func recordPresentationLatency(nanoseconds: UInt64) {
        let milliseconds = Double(nanoseconds) / 1_000_000
        log.info("presentation-latency-ms=\(milliseconds, format: .fixed(precision: 1))")
    }
}

/// MUST 1: emits the replacement stage classification. `ReplacementStageReport`
/// has neither a `String` nor a numeric member, so neither the text nor any
/// measure derived from it can reach the log through this adapter
/// (FR-013／NFR-006).
struct OSLogReplacementDiagnosticsRecorder: ReplacementDiagnosticsRecording {
    private let log = Logger(
        subsystem: "com.systeminteractionfoundation.verification",
        category: "replacement-stage"
    )

    func record(_ report: ReplacementStageReport) {
        let failure = report.failure.map { "\($0)" } ?? "none"
        let focusIsSelf = report.focusedApplicationIsSelf.map(String.init) ?? "na"
        log.info(
            """
            replacement-stage=\(report.stage.rawValue, privacy: .public) \
            failure=\(failure, privacy: .public) \
            focus-is-self=\(focusIsSelf, privacy: .public)
            """
        )
    }
}

/// T-058: emits the monitor path's refusal reason. That path never enters the
/// replacement sequence, so it needs its own category — a refusal that produced
/// no `replacement-stage` line at all is exactly what made the T-055 findings
/// unattributable. `StaleTargetDiagnosticReport` has neither a `String` nor a
/// numeric member, so no content and no measure of content can reach the log
/// through this adapter (FR-013／NFR-006).
struct OSLogStaleTargetDiagnosticsRecorder: StaleTargetDiagnosticsRecording {
    private let log = Logger(
        subsystem: "com.systeminteractionfoundation.verification",
        category: "stale-target-reason"
    )

    func record(_ report: StaleTargetDiagnosticReport) {
        let focusIsSelf = report.focusedApplicationIsSelf.map(String.init) ?? "na"
        log.info(
            """
            stale-target-reason=\(report.reason.rawValue, privacy: .public) \
            focus-is-self=\(focusIsSelf, privacy: .public)
            """
        )
    }
}
