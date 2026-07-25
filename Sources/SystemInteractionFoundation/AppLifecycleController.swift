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

// The authoritative AX replace/restore path is owned by the async
// `AccessibilityGateway` actor; its coordinator integration is driven by the
// T-030 end-to-end failing tests (T-031). Until then every write request is
// refused so the target application is never modified.
final class FailClosedSessionTextTarget: SessionTextTargetAccessing {
    func replace(_ content: SessionContent) -> Bool {
        false
    }

    func validateForRecovery(_ content: SessionContent) -> Bool {
        false
    }

    func restore(_ content: SessionContent) -> Bool {
        false
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
    private let presenter: any PreviewPresenting
    private let transformer = DeterministicTransformer()
    private let mapper = PreviewPresentationMapper()
    private let sessionObserverBridge: SessionObserverBridge

    private var lastTransformed: TransformedText?
    private var isPresenting = false

    init(
        hotKeySystemClient: any HotKeySystemClient,
        permissionChecker: any AccessibilityPermissionChecking,
        settingsOpener: any AccessibilitySettingsOpening,
        secureInputChecker: any SecureEventInputChecking,
        pasteboard: any PasteboardAccessing,
        textTarget: any SessionTextTargetAccessing,
        presenter: any PreviewPresenting
    ) {
        hotKey = GlobalHotKeyRegistrar(systemClient: hotKeySystemClient)
        secureInput = SecureInputGuard(checker: secureInputChecker)
        clipboard = ClipboardPolicy(pasteboard: pasteboard)
        self.presenter = presenter

        let permissionBridge = PermissionFlowBridge()
        permissionFlow = AccessibilityPermissionFlow(
            permission: permissionChecker,
            settings: settingsOpener,
            protectedText: permissionBridge,
            clipboardInput: permissionBridge
        )

        let observerBridge = SessionObserverBridge()
        coordinator = InteractionSessionCoordinator(
            target: textTarget,
            pasteboard: ExplicitActionSessionPasteboard(pasteboard: pasteboard),
            observer: observerBridge
        )
        sessionObserverBridge = observerBridge

        permissionBridge.controller = self
        observerBridge.controller = self
    }

    convenience init() {
        let panelPresenter = PreviewPanelController()
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
            textTarget: FailClosedSessionTextTarget(),
            presenter: panelPresenter
        )
        panelPresenter.onAction = { [weak self] action in
            self?.handle(action)
        }
    }

    @discardableResult
    func start() -> GlobalHotKeyRegistrationOutcome {
        hotKey.register { [weak self] in
            self?.beginDirectInteraction()
        }
    }

    func stop() {
        hotKey.unregister()
        coordinator.close()
        dismissPresentation()
    }

    func beginDirectInteraction() {
        guard secureInput.performIfContentReadAllowed({}) == .allowed else {
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
            if let lastTransformed {
                clipboard.copyResultAfterExplicitAction(lastTransformed)
            }
        case .cancel:
            coordinator.cancel()
        case .restoreOriginal:
            coordinator.recoverOriginal()
        case .copyOriginal:
            coordinator.copyOriginal()
        case .openSettings:
            permissionFlow.openSettingsAfterExplicitAction()
        case .recheckPermission:
            permissionFlow.recheckAfterExplicitAction()
            if permissionFlow.state != .authorized {
                present(.permissionRequired)
            }
        case .useClipboard:
            beginClipboardInputSession()
        case .retry:
            beginDirectInteraction()
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
        // Target capture itself is owned by AccessibilityGateway and is
        // integrated through T-029..T-031.
        coordinator.permissionResolved(granted: true, for: sessionID)
    }

    fileprivate func protectedWriteDidBegin() {
        // The authoritative write path stays fail-closed until the T-030/T-031
        // integration loop wires AccessibilityGateway into the coordinator.
    }

    fileprivate func beginClipboardInputSession() {
        guard
            let text = clipboard.readFromClipboardAfterExplicitAction(),
            !text.isEmpty
        else {
            present(.emptyOrUnsupported)
            return
        }

        let source = SourceText(text)
        let transformed = transformer.transform(source)
        lastTransformed = transformed
        coordinator.beginClipboardSession(source: source, transformed: transformed)
    }

    fileprivate func sessionDidTransition(to state: InteractionSessionState) {
        switch state {
        case .previewing(.ready):
            present(.ready)
        case .previewing(.writeFailed):
            present(.writeFailed)
        case .previewing(.recoveryUnavailable):
            present(.recoveryUnavailable)
        case .ended:
            lastTransformed = nil
            dismissPresentation()
        case .idle, .checkingPermission, .capturingTarget, .applying, .recoverable:
            // Presentation for these transitions is driven by the T-030
            // end-to-end tests and the T-031 assembly.
            break
        }
    }

    private func present(_ status: PreviewStatus) {
        let viewState = mapper.viewState(for: status)
        if isPresenting {
            presenter.update(viewState)
        } else {
            presenter.show(viewState, anchorRect: nil)
            isPresenting = true
        }
    }

    private func dismissPresentation() {
        presenter.dismiss()
        isPresenting = false
    }
}
