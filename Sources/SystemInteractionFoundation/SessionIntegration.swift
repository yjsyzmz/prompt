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
    private(set) var lastRecoveryFailure: DomainFailure?

    init(gateway: AccessibilityGateway) {
        self.gateway = gateway
    }

    func beginSession(targetHandle: TargetHandle, pid: Int32?) {
        self.targetHandle = targetHandle
        targetPID = pid
        recoveryContext = nil
        lastRecoveryFailure = nil
    }

    func endSession() {
        targetHandle = nil
        targetPID = nil
        recoveryContext = nil
        lastRecoveryFailure = nil
    }

    func replace(_ content: SessionContent) -> Result<Void, DomainFailure> {
        guard
            let targetHandle,
            let targetPID,
            content.mode != .clipboardInput
        else {
            return .failure(.unsupportedTarget)
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
            return .success(())
        case .failure(let failure):
            // MUST 2: keep the specific rejection so the panel can explain it.
            return .failure(failure)
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
            self.lastRecoveryFailure = nil
            return true
        case .failure(let failure):
            self.lastRecoveryFailure = failure
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
