import Dispatch
import Foundation

/// Session-scoped target-change monitoring used by the assembly layer.
/// Implementations may only trigger early UI disabling; they never
/// authorize a write — the authoritative validation in
/// `AccessibilityGateway` remains the single write gate.
@MainActor
protocol TargetChangeMonitoring: AnyObject {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    )

    func stopMonitoring()
}

/// Production monitor built from the tested workspace-activation adapter.
/// Element-level `AXObserver` wiring stays inside `AXTargetMonitor` and is
/// attached during the real-environment verification tasks; application
/// switches are the portable stale-target signal available here.
@MainActor
final class WorkspaceTargetChangeMonitor: TargetChangeMonitoring {
    private let workspaceMonitor: any WorkspaceActivationMonitoring
    private let eventReceiver: any AXMonitorEventReceiving

    init(
        eventReceiver: any AXMonitorEventReceiving,
        workspaceMonitor: any WorkspaceActivationMonitoring =
            NSWorkspaceActivationMonitor()
    ) {
        self.eventReceiver = eventReceiver
        self.workspaceMonitor = workspaceMonitor
    }

    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {
        stopMonitoring()
        let envelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
        workspaceMonitor.start { [eventReceiver] in
            Task {
                await eventReceiver.receive(envelope)
            }
        }
    }

    func stopMonitoring() {
        workspaceMonitor.stop()
    }
}

/// Bridges the coordinator's synchronous `SessionTextTargetAccessing`
/// contract onto the async `AccessibilityGateway` actor. The gateway never
/// hops to the main actor, so briefly parking the main thread on a
/// semaphore while the detached task performs the authoritative
/// validation and single write cannot deadlock.
@MainActor
final class GatewaySessionTextTarget: @preconcurrency SessionTextTargetAccessing {
    private let gateway: AccessibilityGateway
    private var targetHandle: TargetHandle?
    private var targetPID: Int32?
    private var recoveryContext: AXRecoveryContext?

    init(gateway: AccessibilityGateway) {
        self.gateway = gateway
    }

    func beginSession(targetHandle: TargetHandle, pid: Int32?) {
        self.targetHandle = targetHandle
        targetPID = pid
        recoveryContext = nil
    }

    func endSession() {
        targetHandle = nil
        targetPID = nil
        recoveryContext = nil
    }

    func replace(_ content: SessionContent) -> Bool {
        guard
            let targetHandle,
            let targetPID,
            content.mode != .clipboardInput
        else {
            return false
        }

        let snapshot = AXWriteSnapshot(
            targetHandle: targetHandle,
            pid: targetPID,
            captureMode: content.mode,
            originalText: content.source,
            transformedText: content.transformed
        )
        let gateway = self.gateway
        let result = Self.performBlocking {
            await gateway.replaceAfterAuthoritativeValidation(snapshot)
        }
        switch result {
        case .success(let context):
            recoveryContext = context
            return true
        case .failure:
            return false
        }
    }

    func validateForRecovery(_ content: SessionContent) -> Bool {
        recoveryContext != nil
    }

    func restore(_ content: SessionContent) -> Bool {
        guard let recoveryContext else {
            return false
        }

        let gateway = self.gateway
        let result = Self.performBlocking {
            await gateway.restoreAfterAuthoritativeValidation(recoveryContext)
        }
        switch result {
        case .success:
            self.recoveryContext = nil
            return true
        case .failure:
            return false
        }
    }

    private static func performBlocking<T: Sendable>(
        _ operation: @escaping @Sendable () async -> T
    ) -> T {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            box.value = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        guard let value = box.value else {
            fatalError("blocking gateway bridge finished without a result")
        }
        return value
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
