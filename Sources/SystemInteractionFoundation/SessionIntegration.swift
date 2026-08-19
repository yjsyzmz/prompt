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

/// Bridges the coordinator's `SessionTextTargetAccessing` contract onto the
/// `AccessibilityGateway` actor. `plan.md` 第 129–136 行 approves an `async`
/// contract, so the calls simply `await` the actor: the main actor is released
/// for the whole write and readback, which is what lets a close, a cancel or a
/// new session be served while a readback is still running (T-065).
///
/// Because the main actor is released, an operation can outlive its session.
/// Every operation therefore captures the session generation it started in and
/// re-checks it after each `await` before touching any shared recovery state —
/// otherwise a stale task could put a finished session's recovery context back,
/// or clear a newer session's (`plan.md` 第 55、387 行).
@MainActor
final class GatewaySessionTextTarget: @preconcurrency SessionTextTargetAccessing {
    private let gateway: AccessibilityGateway
    /// T-053: consulted on `MainActor` at the instant each action runs. Held as
    /// the source of the answer, never as the answer itself.
    private weak var panelFocusOwnership: (any PreviewPanelFocusOwnership)?
    private var targetHandle: TargetHandle?
    private var targetPID: Int32?
    private var recoveryContext: AXRecoveryContext?
    private(set) var lastRecoveryFailure: DomainFailure?

    /// T-065: monotonically increasing, never reused. Any session boundary
    /// invalidates every operation started before it.
    private var sessionGeneration: UInt64 = 0

    init(
        gateway: AccessibilityGateway,
        panelFocusOwnership: (any PreviewPanelFocusOwnership)? = nil
    ) {
        self.gateway = gateway
        self.panelFocusOwnership = panelFocusOwnership
    }

    /// T-053: evaluated here, on `MainActor`, at the instant the action runs.
    /// Deliberately not stored: the panel instance is reused across sessions, so
    /// a remembered `true` would authorise a later session that never earned it.
    private func currentPanelFocusAuthorization() -> PanelFocusAuthorization {
        guard let panelFocusOwnership else {
            return .notOwned
        }
        return PanelFocusAuthorization(
            currentSessionPanelIsKey: panelFocusOwnership.currentSessionPanelIsKey()
        )
    }

    func beginSession(targetHandle: TargetHandle, pid: Int32?) {
        sessionGeneration &+= 1
        self.targetHandle = targetHandle
        targetPID = pid
        recoveryContext = nil
        lastRecoveryFailure = nil
    }

    func endSession() {
        sessionGeneration &+= 1
        targetHandle = nil
        targetPID = nil
        recoveryContext = nil
        lastRecoveryFailure = nil
    }

    func replace(_ content: SessionContent) async -> Result<Void, DomainFailure> {
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
        let panelFocus = currentPanelFocusAuthorization()
        let operationGeneration = sessionGeneration
        let result = await gateway.replaceAfterAuthoritativeValidation(
            snapshot,
            panelFocus: panelFocus
        )
        // T-065: the session may have ended or been replaced while the write and
        // readback ran. Fail closed *before* touching shared recovery state.
        guard operationGeneration == sessionGeneration else {
            return .failure(.invalidTarget)
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

    func validateForRecovery(_ content: SessionContent) async -> Bool {
        recoveryContext != nil
    }

    func restore(_ content: SessionContent) async -> Bool {
        guard let recoveryContext else {
            return false
        }

        let panelFocus = currentPanelFocusAuthorization()
        let operationGeneration = sessionGeneration
        let result = await gateway.restoreAfterAuthoritativeValidation(
            recoveryContext,
            panelFocus: panelFocus
        )
        // T-065: a stale restore must neither clear a newer session's recovery
        // context nor record its own failure against it.
        guard operationGeneration == sessionGeneration else {
            return false
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
}
