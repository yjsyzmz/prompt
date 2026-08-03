import AppKit
import XCTest

/// Implementation Gate REVIEW Finding 2：元素级 `AXObserver` 必须进入生产装配，
/// 使同一应用内的窗口、输入元素、选区或内容变化也能提前禁用"确认替换"
/// （FR-009、AC-009）。监控仍不得授权写入或恢复。
@MainActor
final class ProductionTargetMonitorAssemblyTests: XCTestCase {
    private let sessionID = InteractionSessionID()
    private let handle = TargetHandle()

    /// 生产工厂必须产出组合监控，而不是只监听应用激活的 workspace 监控。
    func testProductionMonitorInstallsElementLevelObserverSource() {
        let scheduler = AssemblySchedulerSpy()
        let workspace = AssemblyWorkspaceSpy()
        let receiver = AssemblyEventReceiverSpy()
        let monitor = AppLifecycleController.makeTargetChangeMonitor(
            eventReceiver: receiver,
            schedulerProvider: { scheduler },
            workspaceActivationMonitor: workspace
        )

        monitor.startMonitoring(sessionID: sessionID, targetHandle: handle)

        XCTAssertEqual(
            scheduler.installCount,
            1,
            "the production monitor must install an element-level observer source"
        )
        XCTAssertEqual(scheduler.installedMode, .common)
        XCTAssertEqual(workspace.startCount, 1)
    }

    func testElementLevelChangeDeliversEnvelopeToGateway() async {
        let scheduler = AssemblySchedulerSpy()
        let receiver = AssemblyEventReceiverSpy()
        let monitor = AppLifecycleController.makeTargetChangeMonitor(
            eventReceiver: receiver,
            schedulerProvider: { scheduler },
            workspaceActivationMonitor: AssemblyWorkspaceSpy()
        )
        monitor.startMonitoring(sessionID: sessionID, targetHandle: handle)

        scheduler.fireObserverCallback()
        await Task.yield()
        await receiver.settle()

        let envelopes = await receiver.received
        XCTAssertEqual(envelopes.count, 1)
        XCTAssertEqual(envelopes.first?.sessionID, sessionID)
        XCTAssertEqual(envelopes.first?.targetHandle, handle)
    }

    func testApplicationActivationStillDeliversEnvelope() async {
        let workspace = AssemblyWorkspaceSpy()
        let receiver = AssemblyEventReceiverSpy()
        let monitor = AppLifecycleController.makeTargetChangeMonitor(
            eventReceiver: receiver,
            schedulerProvider: { AssemblySchedulerSpy() },
            workspaceActivationMonitor: workspace
        )
        monitor.startMonitoring(sessionID: sessionID, targetHandle: handle)

        workspace.fire()
        await Task.yield()
        await receiver.settle()

        let envelopes = await receiver.received
        XCTAssertEqual(envelopes.count, 1)
    }

    func testStopMonitoringRemovesObserverSourceAndWorkspaceObserver() {
        let scheduler = AssemblySchedulerSpy()
        let workspace = AssemblyWorkspaceSpy()
        let monitor = AppLifecycleController.makeTargetChangeMonitor(
            eventReceiver: AssemblyEventReceiverSpy(),
            schedulerProvider: { scheduler },
            workspaceActivationMonitor: workspace
        )

        monitor.startMonitoring(sessionID: sessionID, targetHandle: handle)
        monitor.stopMonitoring()

        XCTAssertEqual(scheduler.removeCount, 1)
        XCTAssertEqual(workspace.stopCount, 1)
    }

    /// 元素级变化必须让预览收回"确认替换"，但不得触发任何写入。
    func testElementLevelChangeDisablesConfirmationWithoutWriting() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let scheduler = AssemblySchedulerSpy()
        let monitor = AppLifecycleController.makeTargetChangeMonitor(
            eventReceiver: gateway,
            schedulerProvider: { scheduler },
            workspaceActivationMonitor: AssemblyWorkspaceSpy()
        )
        let hotKey = AssemblyHotKeyFake()
        let presenter = AssemblyPresenterSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: AssemblyPermissionFake(),
            settingsOpener: AssemblySettingsFake(),
            secureInputChecker: AssemblySecureInputFake(),
            pasteboard: AssemblyPasteboardSpy(),
            gateway: gateway,
            targetMonitor: monitor,
            presenter: presenter
        )
        _ = controller.start()

        hotKey.press()
        await controller.captureWork?.value
        XCTAssertTrue(presenter.lastState?.canConfirmReplacement ?? false)

        scheduler.fireObserverCallback()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(
            presenter.lastState?.canConfirmReplacement ?? true,
            "an element-level change must withdraw the confirmation action"
        )
        XCTAssertEqual(
            host.setterAttemptCount,
            0,
            "monitoring must never authorise a write"
        )
    }
    /// MUST 1：分级诊断必须进入生产装配，否则真实环境跑多少次都拿不到阶段数据。
    func testProductionAssemblyAttachesReplacementDiagnostics() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host,
            diagnostics: AppLifecycleController.makeReplacementDiagnostics()
        )

        let isAttached = await gateway.diagnosticsIsAttached()

        XCTAssertTrue(
            isAttached,
            "the production factory must supply a stage recorder"
        )
    }

    /// T-053：面板焦点归属必须在**每个动作发生时**重新求值，不得缓存为可跨动作
    /// 复用的布尔授权。预览面板是全应用单实例、跨会话复用的，缓存一个 `true`
    /// 等于把授权发给了后续任何一次动作。
    func testPanelFocusIsReevaluatedForEveryAction() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let ownership = PanelFocusOwnershipSpy()
        let target = GatewaySessionTextTarget(
            gateway: gateway,
            panelFocusOwnership: ownership
        )
        guard case .success(let captured) = await gateway.capture(
            sessionID: InteractionSessionID()
        ) else {
            XCTFail("the selection fixture must capture successfully")
            return
        }
        let pid = await gateway.authoritativePID(for: captured.targetHandle)
        target.beginSession(targetHandle: captured.targetHandle, pid: pid)
        let content = SessionContent(
            source: captured.sourceText,
            transformed: DeterministicTransformer().transform(captured.sourceText),
            mode: captured.captureMode
        )

        XCTAssertEqual(
            ownership.callCount,
            0,
            "nothing may be asked before an action runs"
        )
        _ = target.replace(content)
        XCTAssertEqual(ownership.callCount, 1, "the confirm action asks once")
        _ = target.restore(content)
        XCTAssertEqual(
            ownership.callCount,
            2,
            "the restore action must ask again rather than reuse the answer"
        )
    }

    /// 面板不再是 key（已关闭或被其他窗口取代）时，旧的授权不得继续放行。
    func testPanelFocusLostBetweenActionsRevokesTheExemption() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let ownership = PanelFocusOwnershipSpy()
        let target = GatewaySessionTextTarget(
            gateway: gateway,
            panelFocusOwnership: ownership
        )
        guard case .success(let captured) = await gateway.capture(
            sessionID: InteractionSessionID()
        ) else {
            XCTFail("the selection fixture must capture successfully")
            return
        }
        let pid = await gateway.authoritativePID(for: captured.targetHandle)
        target.beginSession(targetHandle: captured.targetHandle, pid: pid)
        let content = SessionContent(
            source: captured.sourceText,
            transformed: DeterministicTransformer().transform(captured.sourceText),
            mode: captured.captureMode
        )
        guard case .success = target.replace(content) else {
            XCTFail("the replacement must succeed before recovery is meaningful")
            return
        }
        let textAfterReplacement = host.fullText

        // The user moves keyboard focus to this process but away from the panel,
        // then asks to restore.
        host.setFrontmostApplication(pid: ProcessInfo.processInfo.processIdentifier)
        ownership.isKey = false

        XCTAssertFalse(
            target.restore(content),
            "a lost panel focus must revoke the exemption"
        )
        XCTAssertEqual(
            host.fullText,
            textAfterReplacement,
            "a refused recovery must not write anything"
        )
    }
}

@MainActor
private final class PanelFocusOwnershipSpy: PreviewPanelFocusOwnership {
    var isKey = true
    private(set) var callCount = 0

    func currentSessionPanelIsKey() -> Bool {
        callCount += 1
        return isKey
    }
}

private final class AssemblySchedulerSpy: AXObserverRunLoopScheduling {
    private(set) var installCount = 0
    private(set) var removeCount = 0
    private(set) var installedMode: AXObserverRunLoopMode?
    private var callback: (@Sendable () -> Void)?

    func installObserverSource(
        mode: AXObserverRunLoopMode,
        callback: @escaping @Sendable () -> Void
    ) {
        installCount += 1
        installedMode = mode
        self.callback = callback
    }

    func removeObserverSource() {
        removeCount += 1
        callback = nil
    }

    func fireObserverCallback() {
        callback?()
    }
}

private final class AssemblyWorkspaceSpy: WorkspaceActivationMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var callback: (@Sendable () -> Void)?

    func start(callback: @escaping @Sendable () -> Void) {
        startCount += 1
        self.callback = callback
    }

    func stop() {
        stopCount += 1
        callback = nil
    }

    func fire() {
        callback?()
    }
}

private actor AssemblyEventReceiverSpy: AXMonitorEventReceiving {
    var received: [AXMonitorCallbackEnvelope] = []

    func receive(_ envelope: AXMonitorCallbackEnvelope) {
        received.append(envelope)
    }

    /// Lets pending delivery tasks land before assertions run.
    func settle() {}
}

@MainActor
private final class AssemblyHotKeyFake: HotKeySystemClient {
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
private final class AssemblyPresenterSpy: PreviewPresenting {
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
private final class AssemblyPermissionFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class AssemblySettingsFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class AssemblySecureInputFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class AssemblyPasteboardSpy: PasteboardAccessing {
    func readStringAfterExplicitAction() -> String? {
        nil
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        true
    }
}
