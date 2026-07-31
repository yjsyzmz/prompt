import AppKit
import Carbon.HIToolbox

// Session coordinator protocols are nonisolated; the @preconcurrency
// conformances assert at runtime that the coordinator only calls them on the
// main actor, where all session work already lives.
@MainActor
final class ExplicitActionSessionPasteboard: @preconcurrency SessionPasteboardAccessing {
    private let pasteboard: any PasteboardAccessing

    init(pasteboard: any PasteboardAccessing) {
        self.pasteboard = pasteboard
    }

    func writeLocalStringAfterExplicitAction(_ text: String) -> Bool {
        pasteboard.writeLocalStringAfterExplicitAction(
            text,
            privacy: .currentHostOnly
        )
    }
}

@MainActor
private final class PermissionFlowBridge:
    PermissionProtectedTextAccessing, ExplicitClipboardInputStarting
{
    weak var controller: AppLifecycleController?

    func beginProtectedRead() {
        controller?.protectedReadDidBegin()
    }

    func beginProtectedWrite() {
        controller?.protectedWriteDidBegin()
    }

    func startClipboardInputAfterExplicitAction() {
        controller?.beginClipboardInputSession()
    }
}

@MainActor
private final class SessionObserverBridge: @preconcurrency SessionStateObserving {
    weak var controller: AppLifecycleController?

    func sessionCoordinatorDidTransition(to state: InteractionSessionState) {
        controller?.sessionDidTransition(to: state)
    }
}

@MainActor
private final class MonitorInvalidationBridge: AXMonitorInvalidationReceiving {
    weak var controller: AppLifecycleController?

    func disableDirectActions(for envelope: AXMonitorCallbackEnvelope) async {
        controller?.targetDidBecomeStale(envelope)
    }
}

/// Breaks the initialisation cycle between the controller and the monitor's
/// scheduler provider without retaining the controller.
@MainActor
private final class ProductionMonitorBox {
    weak var controller: AppLifecycleController?
}

@MainActor
final class AppLifecycleController {
    // The spec keeps the permanent shortcut combination out of scope for 001;
    // this is only the temporary exclusive assembly combination.
    private enum TemporaryHotKey {
        static let keyCode = UInt32(kVK_ANSI_P)
        static let modifiers = UInt32(controlKey | optionKey | cmdKey)
        static let signature: OSType = 0x5349_4631
        static let identifier: UInt32 = 1
    }

    private let hotKey: GlobalHotKeyRegistrar
    private let secureInput: SecureInputGuard
    private let permissionFlow: AccessibilityPermissionFlow
    private let clipboard: ClipboardPolicy
    private let coordinator: InteractionSessionCoordinator
    private let gateway: AccessibilityGateway
    private let targetMonitor: any TargetChangeMonitoring
    private let textTarget: GatewaySessionTextTarget
    private let presenter: any PreviewPresenting
    private let transformer = DeterministicTransformer()
    private let mapper = PreviewPresentationMapper()
    private let sessionObserverBridge: SessionObserverBridge
    private let monitorBridge: MonitorInvalidationBridge
    private let clock: any MonotonicClockReading
    private let latencyRecorder: any PresentationLatencyRecording

    private(set) var captureWork: Task<Void, Never>?
    private(set) var cleanupWork: Task<Void, Never>?

    private var activeSessionID: InteractionSessionID?
    private var activeTargetHandle: TargetHandle?
    private var pendingAnchorRect: CGRect?
    /// Holds the captured element for the current session so that the
    /// production monitor can build an element-level observer scheduler.
    private var activeMonitoringTarget: AXMonitoringTarget?
    private var lastSource: SourceText?
    private var lastTransformed: TransformedText?
    private var pendingCopyRetry: PendingCopyRetry?
    private var isPresenting = false
    private var pendingLatencyStart: UInt64?

    init(
        hotKeySystemClient: any HotKeySystemClient,
        permissionChecker: any AccessibilityPermissionChecking,
        settingsOpener: any AccessibilitySettingsOpening,
        secureInputChecker: any SecureEventInputChecking,
        pasteboard: any PasteboardAccessing,
        gateway: AccessibilityGateway,
        targetMonitor: any TargetChangeMonitoring,
        presenter: any PreviewPresenting,
        clock: any MonotonicClockReading = SystemMonotonicClock(),
        latencyRecorder: any PresentationLatencyRecording =
            OSLogPresentationLatencyRecorder()
    ) {
        hotKey = GlobalHotKeyRegistrar(systemClient: hotKeySystemClient)
        self.clock = clock
        self.latencyRecorder = latencyRecorder
        secureInput = SecureInputGuard(checker: secureInputChecker)
        clipboard = ClipboardPolicy(pasteboard: pasteboard)
        self.gateway = gateway
        self.targetMonitor = targetMonitor
        self.presenter = presenter

        let permissionBridge = PermissionFlowBridge()
        permissionFlow = AccessibilityPermissionFlow(
            permission: permissionChecker,
            settings: settingsOpener,
            protectedText: permissionBridge,
            clipboardInput: permissionBridge
        )

        let sessionTextTarget = GatewaySessionTextTarget(gateway: gateway)
        textTarget = sessionTextTarget

        let observerBridge = SessionObserverBridge()
        coordinator = InteractionSessionCoordinator(
            target: sessionTextTarget,
            pasteboard: ExplicitActionSessionPasteboard(pasteboard: pasteboard),
            observer: observerBridge
        )
        sessionObserverBridge = observerBridge
        monitorBridge = MonitorInvalidationBridge()

        permissionBridge.controller = self
        observerBridge.controller = self
        monitorBridge.controller = self
    }

    convenience init() {
        let gateway = AccessibilityGateway(captureReader: SystemAXCaptureReader())
        let panelPresenter = PreviewPanelController()
        // The scheduler provider is wired to the controller below, once it
        // exists; until then it simply yields no element-level scheduler.
        let monitorBox = ProductionMonitorBox()
        let monitor = AppLifecycleController.makeTargetChangeMonitor(
            eventReceiver: gateway,
            schedulerProvider: { monitorBox.controller?.currentElementObserverScheduler() }
        )
        self.init(
            hotKeySystemClient: HIToolboxHotKeySystemClient(
                keyCode: TemporaryHotKey.keyCode,
                modifiers: TemporaryHotKey.modifiers,
                signature: TemporaryHotKey.signature,
                identifier: TemporaryHotKey.identifier
            ),
            permissionChecker: SystemAccessibilityPermissionChecker(),
            settingsOpener: SystemAccessibilitySettingsOpener(),
            secureInputChecker: HIToolboxSecureEventInputChecker(),
            pasteboard: SystemPasteboardClient(),
            gateway: gateway,
            targetMonitor: monitor,
            presenter: panelPresenter
        )
        monitorBox.controller = self
        panelPresenter.onAction = { [weak self] action in
            self?.handle(action)
        }
    }

    /// FR-009: the production monitor combines the element-level `AXObserver`
    /// with `NSWorkspace` activation. The scheduler is resolved per session
    /// because the captured element only exists after a capture succeeds.
    static func makeTargetChangeMonitor(
        eventReceiver: any AXMonitorEventReceiving,
        schedulerProvider: @escaping () -> (any AXObserverRunLoopScheduling)?,
        workspaceActivationMonitor: any WorkspaceActivationMonitoring =
            NSWorkspaceActivationMonitor()
    ) -> AXTargetMonitor {
        AXTargetMonitor(
            schedulerProvider: schedulerProvider,
            eventReceiver: eventReceiver,
            workspaceActivationMonitor: workspaceActivationMonitor
        )
    }

    /// Builds the element-level scheduler for the session's captured target.
    func currentElementObserverScheduler() -> (any AXObserverRunLoopScheduling)? {
        guard let target = activeMonitoringTarget else {
            return nil
        }
        return SystemAXObserverRunLoopScheduler(
            pid: target.pid,
            targetElement: target.element
        )
    }

    @discardableResult
    func start() -> GlobalHotKeyRegistrationOutcome {
        let outcome = hotKey.register { [weak self] in
            self?.beginDirectInteraction()
        }

        // FR-001 / AC-002: a shortcut that cannot be registered must be
        // explained instead of leaving the app silently unresponsive.
        if outcome != .registered {
            present(.hotKeyConflict)
        }

        return outcome
    }

    func stop() {
        hotKey.unregister()
        coordinator.close()
        dismissPresentation()
    }

    func beginDirectInteraction() {
        // First observable point inside the app; the OS delivery delay before
        // this callback is deliberately outside the measured window.
        pendingLatencyStart = clock.now()

        guard secureInput.performIfContentReadAllowed({}) == .allowed else {
            // FR-013: a refusal must still end any existing session so that no
            // earlier content, target handle or recovery action survives.
            if coordinator.currentSessionID != nil {
                coordinator.close()
            }
            finishSession()
            present(.secureInput)
            return
        }

        coordinator.beginDirectSession()
        permissionFlow.beginCapture()
        if permissionFlow.state != .authorized {
            present(.permissionRequired)
        }
    }

    func handle(_ action: PreviewUserAction) {
        switch action {
        case .confirmReplacement:
            coordinator.confirmReplacement()
        case .copyResult:
            performCopyResult()
        case .cancel:
            coordinator.cancel()
        case .restoreOriginal:
            coordinator.recoverOriginal()
        case .copyOriginal:
            performCopyOriginal()
        case .openSettings:
            permissionFlow.openSettingsAfterExplicitAction()
            // FR-002/AC-003: the Accessibility deep link is not a stable
            // contract, so any fallback must still tell the user where to go.
            if permissionFlow.state != .accessibilitySettingsOpened {
                presentSettingsFallbackGuidance()
            }
        case .recheckPermission:
            permissionFlow.recheckAfterExplicitAction()
            if permissionFlow.state != .authorized {
                presentPermissionRequiredAfterFailedRecheck()
            }
        case .useClipboard:
            beginClipboardInputSession()
        case .retry:
            beginDirectInteraction()
        case .retryCopy:
            // MUST 3: retry the copy that failed, not the whole session.
            switch pendingCopyRetry {
            case .result:
                performCopyResult()
            case .original:
                performCopyOriginal()
            case nil:
                break
            }
        case .retryRegistration:
            if start() == .registered {
                dismissPresentation()
            }
        case .close:
            if coordinator.currentSessionID != nil {
                coordinator.close()
            } else {
                dismissPresentation()
            }
        }
    }

    fileprivate func protectedReadDidBegin() {
        guard let sessionID = coordinator.currentSessionID else {
            return
        }
        coordinator.permissionResolved(granted: true, for: sessionID)
        captureWork = Task { [weak self] in
            await self?.captureTarget(for: sessionID)
        }
    }

    fileprivate func protectedWriteDidBegin() {
        // Direct writes are gated per call by the gateway's authoritative
        // validation; no additional state is required at this hook.
    }

    fileprivate func beginClipboardInputSession() {
        guard let text = clipboard.readFromClipboardAfterExplicitAction() else {
            // NFR-007: an unreadable clipboard is not the same as empty content.
            present(.clipboardReadFailed)
            return
        }
        guard !text.isEmpty else {
            present(.emptyOrUnsupported)
            return
        }

        let source = SourceText(text)
        let transformed = transformer.transform(source)
        lastSource = source
        lastTransformed = transformed
        coordinator.beginClipboardSession(source: source, transformed: transformed)
    }

    fileprivate func targetDidBecomeStale(_ envelope: AXMonitorCallbackEnvelope) {
        guard
            envelope.sessionID == coordinator.currentSessionID,
            envelope.targetHandle == activeTargetHandle,
            coordinator.state == .previewing(.ready)
        else {
            return
        }
        present(.staleTarget)
    }

    fileprivate func sessionDidTransition(to state: InteractionSessionState) {
        switch state {
        case .previewing(.ready):
            presentReady()
        case .previewing(.writeFailed):
            present(.writeFailed)
        case .previewing(.replacementRejected(let failure)):
            // NFR-007: explain the actual rejection instead of implying a write.
            present(replacementRejectionStatus(for: failure))
        case .previewing(.recoveryUnavailable):
            presentRecoveryUnavailable()
        case .recoverable:
            presentRecoverable()
        case .ended:
            finishSession()
        case .idle, .checkingPermission, .capturingTarget, .applying:
            break
        }
    }

    private func captureTarget(for sessionID: InteractionSessionID) async {
        let result = await gateway.capture(sessionID: sessionID)

        switch result {
        case .success(let captured):
            // Every early return below must release the handle this capture
            // created, otherwise a cancelled or replaced session leaks it.
            guard coordinator.currentSessionID == sessionID else {
                await releaseStaleCapture(
                    sessionID: sessionID,
                    targetHandle: captured.targetHandle
                )
                return
            }
            let pid = await gateway.authoritativePID(for: captured.targetHandle)
            let monitoringTarget = await gateway.monitoringTarget(
                for: captured.targetHandle
            )
            guard coordinator.currentSessionID == sessionID else {
                await releaseStaleCapture(
                    sessionID: sessionID,
                    targetHandle: captured.targetHandle
                )
                return
            }

            activeSessionID = sessionID
            activeTargetHandle = captured.targetHandle
            activeMonitoringTarget = monitoringTarget
            pendingAnchorRect = captured.anchorRect
            textTarget.beginSession(
                targetHandle: captured.targetHandle,
                pid: pid
            )
            let transformed = transformer.transform(captured.sourceText)
            lastSource = captured.sourceText
            lastTransformed = transformed

            await gateway.activateMonitoring(
                sessionID: sessionID,
                targetHandle: captured.targetHandle,
                invalidationSink: monitorBridge
            )
            guard coordinator.currentSessionID == sessionID else {
                // Monitoring was already enabled for this session; undo it as
                // well as releasing the handle.
                clearActiveTargetState(for: sessionID)
                await releaseStaleCapture(
                    sessionID: sessionID,
                    targetHandle: captured.targetHandle
                )
                return
            }
            targetMonitor.startMonitoring(
                sessionID: sessionID,
                targetHandle: captured.targetHandle
            )
            coordinator.captureCompleted(
                source: captured.sourceText,
                transformed: transformed,
                mode: captured.captureMode,
                for: sessionID
            )
        case .failure(let failure):
            guard coordinator.currentSessionID == sessionID else {
                return
            }
            coordinator.cancel()
            present(previewStatus(for: failure))
        }
    }

    /// Releases the AX handle and monitoring created by a capture whose session
    /// is no longer current.
    private func releaseStaleCapture(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) async {
        await gateway.deactivateMonitoring(for: sessionID)
        await gateway.releaseTarget(targetHandle)
    }

    /// Clears controller-held references for a session that turned stale after
    /// they were assigned.
    private func clearActiveTargetState(for sessionID: InteractionSessionID) {
        guard activeSessionID == sessionID else {
            return
        }
        activeSessionID = nil
        activeTargetHandle = nil
        activeMonitoringTarget = nil
        pendingAnchorRect = nil
        lastSource = nil
        lastTransformed = nil
        textTarget.endSession()
    }

    /// MUST 2: maps an authoritative-validation rejection onto the status that
    /// describes it. None of these paths reached a setter, so none of them may
    /// be presented as a failed write.
    private func replacementRejectionStatus(
        for failure: DomainFailure
    ) -> PreviewStatus {
        switch failure {
        case .secureInputActive:
            return .secureInput
        case .accessibilityPermissionRequired:
            return .permissionRequired
        case .attributeNotSettable, .unsupportedTarget:
            return .targetNotWritable
        default:
            return .staleTarget
        }
    }

    private func previewStatus(for failure: DomainFailure) -> PreviewStatus {        switch failure {
        case .secureInputActive:
            return .secureInput
        case .accessibilityPermissionRequired:
            return .permissionRequired
        default:
            return .emptyOrUnsupported
        }
    }

    private func presentReady() {
        let baseState = mapper.viewState(for: .ready)
        let buttons = coordinator.availableActions.contains(.confirmReplacement)
            ? baseState.buttons
            : baseState.buttons.filter { $0.action != .confirmReplacement }
        presentViewState(
            PreviewViewState(
                message: baseState.message,
                buttons: buttons,
                sourceText: lastSource?.value,
                resultText: lastTransformed?.value
            )
        )
    }

    private func presentRecoverable() {
        presentViewState(
            PreviewViewState(
                message: "已替换所选文字，原文仍可恢复。",
                buttons: [
                    PreviewButton(
                        action: .restoreOriginal,
                        title: "恢复原文",
                        isEnabled: true
                    ),
                    PreviewButton(action: .copyResult, title: "复制结果", isEnabled: true),
                    PreviewButton(action: .close, title: "关闭", isEnabled: true),
                ],
                sourceText: lastSource?.value,
                resultText: lastTransformed?.value
            )
        )
    }

    private func presentRecoveryUnavailable() {
        let baseState = mapper.viewState(for: .recoveryUnavailable)
        let message: String
        switch textTarget.lastRecoveryFailure {
        case .invalidTarget:
            message = "目标应用、窗口或输入位置已经变化，无法直接恢复。"
        case .recoveryTargetChanged:
            message = "目标文字已经变化，无法直接恢复。"
        case .attributeNotSettable:
            message = "当前输入位置已经不可写，无法直接恢复。"
        case .secureInputActive:
            message = "当前输入位置处于安全输入状态，无法直接恢复。"
        default:
            message = baseState.message
        }
        presentViewState(
            PreviewViewState(message: message, buttons: baseState.buttons)
        )
    }

    /// MUST 3: which explicit copy failed, so that a retry repeats that copy.
    private enum PendingCopyRetry {
        case result
        case original
    }

    private func performCopyResult() {
        guard let lastTransformed else {
            return
        }
        if clipboard.copyResultAfterExplicitAction(lastTransformed) {
            pendingCopyRetry = nil
            sessionDidTransition(to: coordinator.state)
        } else {
            // NFR-007: an explicit copy that failed must not look like it
            // succeeded, and the retry must repeat this same copy.
            pendingCopyRetry = .result
            present(.clipboardWriteFailed)
        }
    }

    private func performCopyOriginal() {
        if coordinator.copyOriginal() {
            pendingCopyRetry = nil
            sessionDidTransition(to: coordinator.state)
        } else {
            pendingCopyRetry = .original
            present(.clipboardWriteFailed)
        }
    }

    private func present(_ status: PreviewStatus) {
        presentViewState(mapper.viewState(for: status))
    }

    private func presentSettingsFallbackGuidance() {
        let baseState = mapper.viewState(for: .permissionRequired)
        presentViewState(
            PreviewViewState(
                message: "未能直接打开辅助功能设置。请在「系统设置」中前往「隐私与安全性」→「辅助功能」，启用本应用后再点重新检测。",
                buttons: baseState.buttons
            )
        )
    }

    private func presentPermissionRequiredAfterFailedRecheck() {
        let baseState = mapper.viewState(for: .permissionRequired)
        presentViewState(
            PreviewViewState(
                message: "仍未检测到辅助功能权限。请在系统设置中启用本应用后，关闭并重新打开应用，再重新检测。",
                buttons: baseState.buttons
            )
        )
    }

    private func presentViewState(_ viewState: PreviewViewState) {
        if isPresenting {
            presenter.update(viewState)
        } else {
            presenter.show(viewState, anchorRect: pendingAnchorRect)
            isPresenting = true
        }

        if let start = pendingLatencyStart {
            pendingLatencyStart = nil
            latencyRecorder.recordPresentationLatency(
                nanoseconds: clock.now() &- start
            )
        }
    }

    private func finishSession() {
        activeMonitoringTarget = nil
        lastSource = nil
        lastTransformed = nil
        pendingAnchorRect = nil
        pendingCopyRetry = nil
        textTarget.endSession()
        targetMonitor.stopMonitoring()
        dismissPresentation()

        if let sessionID = activeSessionID, let targetHandle = activeTargetHandle {
            activeSessionID = nil
            activeTargetHandle = nil
            cleanupWork = Task { [gateway] in
                await gateway.deactivateMonitoring(for: sessionID)
                await gateway.releaseTarget(targetHandle)
            }
        }
    }

    private func dismissPresentation() {
        presenter.dismiss()
        isPresenting = false
    }
}
