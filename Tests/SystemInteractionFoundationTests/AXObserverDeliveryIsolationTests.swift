import Foundation
import XCTest

@MainActor
final class AXObserverDeliveryIsolationTests: XCTestCase {
    private let sessionID = InteractionSessionID()
    private let targetHandle = TargetHandle()

    func testStartInstallsObserverSourceOnMainRunLoopCommonMode() {
        let scheduler = AXObserverRunLoopSchedulerSpy()
        let receiver = AXMonitorIngressSpy()
        let monitor = AXTargetMonitor(
            runLoopScheduler: scheduler,
            eventReceiver: receiver
        )

        monitor.startMonitoring(
            sessionID: sessionID,
            targetHandle: targetHandle
        )

        XCTAssertEqual(scheduler.installationCount, 1)
        XCTAssertTrue(scheduler.installationWasOnMainThread)
        XCTAssertEqual(scheduler.installedMode, .common)
    }

    func testCallbackEnvelopeContainsOnlySessionAndTargetIdentifiers() {
        let envelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )

        XCTAssertEqual(envelope.sessionID, sessionID)
        XCTAssertEqual(envelope.targetHandle, targetHandle)
        XCTAssertEqual(
            Mirror(reflecting: envelope).children.compactMap(\.label),
            ["sessionID", "targetHandle"]
        )
    }

    func testSystemCallbackReturnsThenEventEntersActorAsynchronously() async {
        let scheduler = AXObserverRunLoopSchedulerSpy()
        let receiver = AXMonitorIngressSpy()
        let monitor = AXTargetMonitor(
            runLoopScheduler: scheduler,
            eventReceiver: receiver
        )
        monitor.startMonitoring(
            sessionID: sessionID,
            targetHandle: targetHandle
        )

        scheduler.fireInstalledCallback()

        XCTAssertTrue(scheduler.callbackReturnedSynchronously)
        await waitUntil { await receiver.deliveryCount == 1 }
        let envelopes = await receiver.envelopes
        XCTAssertEqual(
            envelopes,
            [
                AXMonitorCallbackEnvelope(
                    sessionID: sessionID,
                    targetHandle: targetHandle
                )
            ]
        )
    }

    func testWorkspaceActivationAlsoEntersActorAsynchronously() async {
        let scheduler = AXObserverRunLoopSchedulerSpy()
        let workspace = WorkspaceActivationMonitorSpy()
        let receiver = AXMonitorIngressSpy()
        let monitor = AXTargetMonitor(
            runLoopScheduler: scheduler,
            eventReceiver: receiver,
            workspaceActivationMonitor: workspace
        )
        monitor.startMonitoring(
            sessionID: sessionID,
            targetHandle: targetHandle
        )

        workspace.fireActivation()

        XCTAssertTrue(workspace.callbackReturnedSynchronously)
        await waitUntil { await receiver.deliveryCount == 1 }
        let envelopes = await receiver.envelopes
        XCTAssertEqual(
            envelopes,
            [
                AXMonitorCallbackEnvelope(
                    sessionID: sessionID,
                    targetHandle: targetHandle
                )
            ]
        )
    }

    func testStopReleasesRunLoopSourceAndWorkspaceObservationOnce() {
        let scheduler = AXObserverRunLoopSchedulerSpy()
        let workspace = WorkspaceActivationMonitorSpy()
        let monitor = AXTargetMonitor(
            runLoopScheduler: scheduler,
            eventReceiver: AXMonitorIngressSpy(),
            workspaceActivationMonitor: workspace
        )
        monitor.startMonitoring(
            sessionID: sessionID,
            targetHandle: targetHandle
        )

        monitor.stopMonitoring()
        monitor.stopMonitoring()

        XCTAssertEqual(scheduler.removalCount, 1)
        XCTAssertEqual(workspace.stopCount, 1)
    }

    func testStaleSessionCallbackIsIgnoredInsideActorRouter() async {
        let sink = AXMonitorInvalidationSinkSpy()
        let router = AXMonitorEventRouter(invalidationSink: sink)
        let currentSessionID = InteractionSessionID()
        let currentTargetHandle = TargetHandle()
        await router.activate(
            sessionID: currentSessionID,
            targetHandle: currentTargetHandle
        )

        await router.receive(
            AXMonitorCallbackEnvelope(
                sessionID: sessionID,
                targetHandle: targetHandle
            )
        )

        let invalidationCount = await sink.invalidationCount
        XCTAssertEqual(invalidationCount, 0)
    }

    func testCurrentSessionCallbackOnlyDisablesDirectActions() async {
        let sink = AXMonitorInvalidationSinkSpy()
        let router = AXMonitorEventRouter(invalidationSink: sink)
        await router.activate(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
        let envelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )

        await router.receive(envelope)

        let invalidations = await sink.invalidations
        XCTAssertEqual(invalidations, [envelope])
    }

    func testProductionMonitorCannotAuthorizeReplacementOrRecovery() throws {
        let testBundle = Bundle(for: AXObserverDeliveryIsolationTests.self)
        guard let sourceURL = testBundle.url(
            forResource: "ExternalTargetMonitor",
            withExtension: "swift"
        ) else {
            XCTFail("Expected the production monitor source audit resource")
            return
        }
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let forbiddenAuthoritySymbols = [
            "replaceAfterAuthoritativeValidation",
            "restoreAfterAuthoritativeValidation",
            "AXUIElementSetAttributeValue",
            "setSelectedText(",
            "setWholeValue(",
        ]

        for symbol in forbiddenAuthoritySymbols {
            XCTAssertFalse(
                source.contains(symbol),
                "Monitor must not contain write authority: \(symbol)"
            )
        }
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        attempts: Int = 100
    ) async {
        for _ in 0..<attempts {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous actor delivery")
    }
}

@MainActor
private final class AXObserverRunLoopSchedulerSpy: AXObserverRunLoopScheduling {
    private var callback: (@Sendable () -> Void)?
    private(set) var installationCount = 0
    private(set) var installationWasOnMainThread = false
    private(set) var installedMode: AXObserverRunLoopMode?
    private(set) var callbackReturnedSynchronously = false
    private(set) var removalCount = 0

    func installObserverSource(
        mode: AXObserverRunLoopMode,
        callback: @escaping @Sendable () -> Void
    ) {
        installationCount += 1
        installationWasOnMainThread = Thread.isMainThread
        installedMode = mode
        self.callback = callback
    }

    func fireInstalledCallback() {
        callbackReturnedSynchronously = false
        callback?()
        callbackReturnedSynchronously = true
    }

    func removeObserverSource() {
        removalCount += 1
        callback = nil
    }
}

@MainActor
private final class WorkspaceActivationMonitorSpy: WorkspaceActivationMonitoring {
    private var callback: (@Sendable () -> Void)?
    private(set) var stopCount = 0
    private(set) var callbackReturnedSynchronously = false

    func start(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
    }

    func stop() {
        stopCount += 1
        callback = nil
    }

    func fireActivation() {
        callbackReturnedSynchronously = false
        callback?()
        callbackReturnedSynchronously = true
    }
}

private actor AXMonitorIngressSpy: AXMonitorEventReceiving {
    private(set) var envelopes: [AXMonitorCallbackEnvelope] = []

    var deliveryCount: Int {
        envelopes.count
    }

    func receive(_ envelope: AXMonitorCallbackEnvelope) async {
        envelopes.append(envelope)
    }
}

private actor AXMonitorInvalidationSinkSpy: AXMonitorInvalidationReceiving {
    private(set) var invalidations: [AXMonitorCallbackEnvelope] = []

    var invalidationCount: Int {
        invalidations.count
    }

    func disableDirectActions(
        for envelope: AXMonitorCallbackEnvelope
    ) async {
        invalidations.append(envelope)
    }
}
