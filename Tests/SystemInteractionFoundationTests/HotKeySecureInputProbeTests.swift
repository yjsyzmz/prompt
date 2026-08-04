import Foundation
import XCTest

@MainActor
final class HotKeySecureInputProbeTests: XCTestCase {
    func testExclusiveHotKeyRegistrationSucceeds() {
        let token = HotKeyRegistrationToken(id: 41)
        let systemClient = HotKeySystemClientSpy(
            registrationOutcome: .registered(token)
        )
        let registrar = GlobalHotKeyRegistrar(systemClient: systemClient)

        let outcome = registrar.register(onPress: {})

        XCTAssertEqual(outcome, .registered)
        XCTAssertEqual(systemClient.registerCallCount, 1)
    }

    func testExclusiveHotKeyConflictIsReported() {
        let systemClient = HotKeySystemClientSpy(
            registrationOutcome: .conflict
        )
        let registrar = GlobalHotKeyRegistrar(systemClient: systemClient)

        let outcome = registrar.register(onPress: {})

        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(systemClient.registerCallCount, 1)
    }

    func testUnregisterReleasesOnlyTheActiveRegistration() {
        let token = HotKeyRegistrationToken(id: 42)
        let systemClient = HotKeySystemClientSpy(
            registrationOutcome: .registered(token)
        )
        let registrar = GlobalHotKeyRegistrar(systemClient: systemClient)
        XCTAssertEqual(registrar.register(onPress: {}), .registered)

        registrar.unregister()
        registrar.unregister()

        XCTAssertEqual(systemClient.unregisteredTokens, [token])
    }

    func testRepeatedSystemCallbacksAreForwardedExactlyOnceEach() {
        let systemClient = HotKeySystemClientSpy(
            registrationOutcome: .registered(HotKeyRegistrationToken(id: 43))
        )
        let registrar = GlobalHotKeyRegistrar(systemClient: systemClient)
        var callbackCount = 0
        XCTAssertEqual(
            registrar.register(onPress: { callbackCount += 1 }),
            .registered
        )

        systemClient.fireRegisteredCallback()
        systemClient.fireRegisteredCallback()

        XCTAssertEqual(callbackCount, 2)
    }

    func testSecureEventInputBlocksBeforeAnyContentRead() {
        let checker = SecureEventInputCheckerStub(isEnabled: true)
        let guardUnderTest = SecureInputGuard(checker: checker)
        let contentReader = ContentReaderSpy()

        let decision = guardUnderTest.performIfContentReadAllowed {
            contentReader.readContent()
        }

        XCTAssertEqual(decision, .blocked)
        XCTAssertEqual(checker.checkCallCount, 1)
        XCTAssertEqual(contentReader.readCallCount, 0)
    }

    func testMonotonicClockIsFirstSampledInsideHotKeyCallback() {
        let systemClient = HotKeySystemClientSpy(
            registrationOutcome: .registered(HotKeyRegistrationToken(id: 44))
        )
        let registrar = GlobalHotKeyRegistrar(systemClient: systemClient)
        let monotonicClock = MonotonicClockStub(samples: [9_001])
        let probeClock = CapabilityProbeClock(clock: monotonicClock)
        var callbackStart: UInt64?

        XCTAssertEqual(
            registrar.register(onPress: {
                callbackStart = probeClock.sampleAtHotKeyCallback()
            }),
            .registered
        )
        XCTAssertEqual(monotonicClock.sampleCallCount, 0)

        systemClient.fireRegisteredCallback()

        XCTAssertEqual(callbackStart, 9_001)
        XCTAssertEqual(monotonicClock.sampleCallCount, 1)
    }

    func testProductionSourcesDoNotUseGeneralKeyMonitoringAPIs() throws {
        let forbiddenSymbols = [
            "CGEventTap",
            "CGEvent.tapCreate",
            "NSEvent.addGlobalMonitorForEvents",
            "NSEvent.addLocalMonitorForEvents",
            "IOHIDManager",
            "kTCCServiceListenEvent",
        ]
        let testBundle = Bundle(for: HotKeySecureInputProbeTests.self)
        guard let sourceFile = testBundle.url(
            forResource: "SystemInteractionAdapters",
            withExtension: "swift"
        ) else {
            XCTFail("Expected the production adapter source audit resource")
            return
        }
        let source = try String(contentsOf: sourceFile, encoding: .utf8)

        for forbiddenSymbol in forbiddenSymbols {
            XCTAssertFalse(
                source.contains(forbiddenSymbol),
                "Production source must not use general key monitoring API \(forbiddenSymbol)"
            )
        }
    }
}

@MainActor
private final class HotKeySystemClientSpy: HotKeySystemClient {
    private let registrationOutcome: HotKeySystemRegistrationOutcome
    private var registeredCallback: (() -> Void)?

    private(set) var registerCallCount = 0
    private(set) var unregisteredTokens: [HotKeyRegistrationToken] = []

    init(registrationOutcome: HotKeySystemRegistrationOutcome) {
        self.registrationOutcome = registrationOutcome
    }

    func registerExclusive(callback: @escaping () -> Void) -> HotKeySystemRegistrationOutcome {
        registerCallCount += 1
        registeredCallback = callback
        return registrationOutcome
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        unregisteredTokens.append(token)
    }

    func fireRegisteredCallback() {
        registeredCallback?()
    }
}

private final class SecureEventInputCheckerStub: SecureEventInputChecking {
    private let isEnabled: Bool
    private(set) var checkCallCount = 0

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func isSecureEventInputEnabled() -> Bool {
        checkCallCount += 1
        return isEnabled
    }
}

private final class ContentReaderSpy {
    private(set) var readCallCount = 0

    func readContent() {
        readCallCount += 1
    }
}

private final class MonotonicClockStub: MonotonicClockReading, @unchecked Sendable {
    private var samples: [UInt64]
    private(set) var sampleCallCount = 0

    init(samples: [UInt64]) {
        self.samples = samples
    }

    func now() -> UInt64 {
        sampleCallCount += 1
        return samples.removeFirst()
    }
}
