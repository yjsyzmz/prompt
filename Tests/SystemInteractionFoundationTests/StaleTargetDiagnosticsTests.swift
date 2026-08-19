import Foundation
import XCTest

/// T-058：目标变化监听器路径的分级诊断。
///
/// `AppLifecycleController.targetDidBecomeStale` 在监听器触发且会话处于
/// `previewing(.ready)` 时直接呈现「原输入位置已经变化」，此前该路径没有任何
/// 埋点。T-055 抓到 22 条阶段记录里 A1–A4 拒绝为零条——因为替换从未被请求，
/// 拒绝发生在替换序列之前，所以 `ReplacementStage` 根本描述不到它。
///
/// 本套件断言：监听器导致的拒绝会产生**恰好一条**可辨认的诊断记录，且该记录
/// 能区分「窗口变化／元素变化／焦点应用变化」三种依据；同时断言监听器的判定
/// 行为没有改变，诊断不含任何内容或长度（FR-013／NFR-006，沿用 T-052 边界）。
@MainActor
final class StaleTargetDiagnosticsTests: XCTestCase {
    // MARK: - 三种判定依据必须彼此可分

    func testWindowChangeIsClassifiedAsWindowIdentity() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.switchWindow()

        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(report?.reason, .windowIdentityChanged)
        XCTAssertNil(
            report?.focusedApplicationIsSelf,
            "only the focused-application reason evaluates focus ownership"
        )
    }

    func testElementInvalidationIsClassifiedAsElementIdentity() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.invalidateElement()

        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(report?.reason, .elementIdentityChanged)
    }

    func testExternalFocusChangeIsClassifiedAsFocusedApplication() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.moveFocusToDifferentApplication()

        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(report?.reason, .focusedApplicationChanged)
        XCTAssertEqual(
            report?.focusedApplicationIsSelf,
            false,
            "a genuinely different application is not this process"
        )
    }

    func testTerminatedApplicationIsClassifiedAsItsOwnReason() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.terminateApplication()

        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(report?.reason, .applicationTerminated)
    }

    /// 三种依据在实现里都通向同一个 `.staleTarget` 文案，所以只有原因分类能把
    /// 它们分开——这正是 T-063 逐次归因所依赖的性质。
    func testTheThreeMonitorReasonsAreAllDistinct() async {
        var reasons: [StaleTargetReason] = []
        for mutate in [
            { (host: SyntheticAXTextHost) in host.switchWindow() },
            { (host: SyntheticAXTextHost) in host.invalidateElement() },
            { (host: SyntheticAXTextHost) in host.moveFocusToDifferentApplication() },
        ] {
            let env = StaleTargetEnvironment.make()
            await env.reachReadyPreview()
            mutate(env.host)
            if let report = await env.fireMonitorAndCollectReport() {
                reasons.append(report.reason)
            }
        }

        XCTAssertEqual(reasons.count, 3)
        XCTAssertEqual(
            Set(reasons).count,
            3,
            "all three refusals present the same copy, so only the reason separates them"
        )
    }

    // MARK: - 无法归因的情形必须如实报告，不得猜测

    /// ChatGPT 二次替换场景：在同一输入框完成一轮「确认替换 → 恢复原文」后再次
    /// 触发，面板刚就绪就被判目标变化。若此时窗口、元素、焦点应用三项身份全部
    /// 仍然匹配，记录必须如实说明「身份未变」，而不是含糊地报成某种变化——
    /// T-064 的根因判断只能建立在这种可辨认的记录上。
    func testSecondSessionRefusalWithIntactIdentityIsReportedAsIntact() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()

        env.controller.handle(.confirmReplacement)
        await env.controller.applyWork?.value
        env.host.collapseSelectionAfterWrite()
        env.controller.handle(.restoreOriginal)
        await env.controller.recoverWork?.value
        await env.controller.cleanupWork?.value

        await env.reachReadyPreview()
        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(
            report?.reason,
            .identityIntact,
            "a refusal that no identity check explains must say so"
        )
    }

    /// T-053：豁免范围是当前会话的预览面板。真人用鼠标点按钮时面板会成为 key
    /// window，`kAXFocusedApplicationAttribute` 随之指向本进程——这不得被记成
    /// 「焦点应用变化」，否则 T-063 的每一次记录都会被这条噪声污染。
    func testSessionPanelHoldingFocusIsNotReportedAsAFocusChange() async {
        let env = StaleTargetEnvironment.make(panelIsKey: true)
        await env.reachReadyPreview()
        env.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(
            report?.reason,
            .identityIntact,
            "the approved A2 exempts this tool's own panel from the check"
        )
    }

    /// 焦点落在本进程但面板并未持有焦点时，仍须报「焦点应用变化」，并记下焦点
    /// 就在本进程这一事实。
    func testFocusOnThisProcessWithoutPanelKeyReportsFocusOwnership() async {
        let env = StaleTargetEnvironment.make(panelIsKey: false)
        await env.reachReadyPreview()
        env.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let report = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(report?.reason, .focusedApplicationChanged)
        XCTAssertEqual(
            report?.focusedApplicationIsSelf,
            true,
            "the report must still say the focus was on this process"
        )
    }

    // MARK: - 只让原因可见，不改变监听器的判定行为

    func testTheRefusalItselfIsUnchanged() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.switchWindow()
        let presentedBefore = env.presenter.presentedStateCount

        _ = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(
            env.presenter.presentedStateCount,
            presentedBefore + 1,
            "instrumentation must not add or remove a presentation"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            PreviewPresentationMapper().viewState(for: .staleTarget).message,
            "the copy the user sees must stay exactly as it was"
        )
        XCTAssertEqual(
            env.host.setterAttemptCount,
            0,
            "a monitor refusal must not write anything"
        )
    }

    func testExactlyOneReportPerRefusal() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.switchWindow()

        _ = await env.fireMonitorAndCollectReport()

        XCTAssertEqual(
            env.recorder.snapshot().count,
            1,
            "one refusal must produce one attributable record"
        )
    }

    /// 会话已结束后的回调此前就被忽略，加了埋点也不得因此产生记录。
    func testCallbackAfterSessionEndProducesNoReport() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.controller.handle(.cancel)
        await env.controller.cleanupWork?.value

        _ = await env.fireMonitorAndCollectReport()

        XCTAssertTrue(
            env.recorder.snapshot().isEmpty,
            "an ignored callback is not a refusal and must not be recorded"
        )
    }

    // MARK: - 隐私边界（沿用 T-052）

    func testReportHasNoNumericContentMeasureField() async {
        let env = StaleTargetEnvironment.make()
        await env.reachReadyPreview()
        env.host.switchWindow()
        _ = await env.fireMonitorAndCollectReport()

        let reports = env.recorder.snapshot()
        XCTAssertFalse(reports.isEmpty)
        for report in reports {
            for child in Mirror(reflecting: report).children {
                let typeName = String(describing: type(of: child.value))
                XCTAssertFalse(
                    typeName.contains("Int"),
                    """
                    FR-013: a stale-target report may not carry a numeric \
                    measure of user text; found \(child.label ?? "?") of type \
                    \(typeName)
                    """
                )
            }
        }
    }

    func testNoReportEverCarriesContentOrDigits() async {
        let marker = SyntheticAXTextHost.syntheticMarker
        var descriptions: [String] = []

        for mutate in [
            { (host: SyntheticAXTextHost) in host.switchWindow() },
            { (host: SyntheticAXTextHost) in host.invalidateElement() },
            { (host: SyntheticAXTextHost) in host.moveFocusToDifferentApplication() },
            { (host: SyntheticAXTextHost) in host.terminateApplication() },
            { (_: SyntheticAXTextHost) in },
        ] {
            let env = StaleTargetEnvironment.make()
            await env.reachReadyPreview()
            mutate(env.host)
            _ = await env.fireMonitorAndCollectReport()
            descriptions += env.recorder.snapshot().map { String(describing: $0) }
        }

        XCTAssertFalse(descriptions.isEmpty)
        for description in descriptions {
            XCTAssertFalse(
                description.contains(marker),
                "FR-013: diagnostics must not carry captured or written text"
            )
            XCTAssertFalse(description.contains("文字"))
            XCTAssertNil(
                description.rangeOfCharacter(from: .decimalDigits),
                "FR-013: diagnostics must not expose any digit derived from content"
            )
        }
    }

    // MARK: - 生产装配

    /// 埋点若不进生产装配，真实环境跑多少次都拿不到原因分类。
    func testProductionAssemblyAttachesStaleTargetDiagnostics() {
        let host = SyntheticAXTextHost.selectionFixture()
        let controller = AppLifecycleController(
            hotKeySystemClient: StaleHotKeyClientFake(),
            permissionChecker: StalePermissionCheckerFake(),
            settingsOpener: StaleSettingsOpenerFake(),
            secureInputChecker: StaleSecureInputCheckerFake(),
            pasteboard: StalePasteboardSpy(),
            gateway: AccessibilityGateway(
                captureReader: host,
                authoritativeTarget: host
            ),
            targetMonitor: StaleTargetMonitorSpy(),
            presenter: StalePresenterSpy(),
            staleTargetDiagnostics: AppLifecycleController.makeStaleTargetDiagnostics()
        )

        XCTAssertTrue(
            controller.staleTargetDiagnosticsIsAttached,
            "the production factory must supply a stale-target recorder"
        )
    }
}

// MARK: - Environment

@MainActor
private struct StaleTargetEnvironment {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let controller: AppLifecycleController
    let hotKey: StaleHotKeyClientFake
    let presenter: StalePresenterSpy
    let monitor: StaleTargetMonitorSpy
    let recorder: StaleTargetRecorderSpy

    static func make(panelIsKey: Bool? = nil) -> StaleTargetEnvironment {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = StaleHotKeyClientFake()
        let presenter = StalePresenterSpy()
        presenter.panelIsKey = panelIsKey
        let monitor = StaleTargetMonitorSpy()
        let recorder = StaleTargetRecorderSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: StalePermissionCheckerFake(),
            settingsOpener: StaleSettingsOpenerFake(),
            secureInputChecker: StaleSecureInputCheckerFake(),
            pasteboard: StalePasteboardSpy(),
            gateway: gateway,
            targetMonitor: monitor,
            presenter: presenter,
            staleTargetDiagnostics: recorder
        )
        _ = controller.start()
        return StaleTargetEnvironment(
            host: host,
            gateway: gateway,
            controller: controller,
            hotKey: hotKey,
            presenter: presenter,
            monitor: monitor,
            recorder: recorder
        )
    }

    /// Drives the real hot key → permission → capture path until the preview is
    /// ready, which is the only state in which the monitor refuses.
    func reachReadyPreview() async {
        hotKey.press()
        await controller.captureWork?.value
    }

    /// Delivers a monitor callback through the production route — the gateway
    /// forwards it to the controller's own invalidation bridge — and returns the
    /// single report it produced.
    func fireMonitorAndCollectReport() async -> StaleTargetDiagnosticReport? {
        guard let envelope = monitor.lastEnvelope else {
            XCTFail("monitoring must have started before a callback can arrive")
            return nil
        }
        await gateway.receive(envelope)
        await controller.staleTargetDiagnosticsWork?.value
        return recorder.snapshot().last
    }
}

// MARK: - Fakes and spies

private final class StaleTargetRecorderSpy:
    StaleTargetDiagnosticsRecording, @unchecked Sendable
{
    private let lock = NSLock()
    private var reports: [StaleTargetDiagnosticReport] = []

    func record(_ report: StaleTargetDiagnosticReport) {
        lock.lock()
        defer { lock.unlock() }
        reports.append(report)
    }

    func snapshot() -> [StaleTargetDiagnosticReport] {
        lock.lock()
        defer { lock.unlock() }
        return reports
    }
}

@MainActor
private final class StaleHotKeyClientFake: HotKeySystemClient {
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
private final class StalePermissionCheckerFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class StaleSettingsOpenerFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class StaleSecureInputCheckerFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class StalePasteboardSpy: PasteboardAccessing {
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

/// `panelIsKey == nil` models a presenter that cannot answer the question at
/// all, which must stay unexempted (`PanelFocusAuthorization.notOwned`).
@MainActor
private final class StalePresenterSpy: PreviewPresenting, PreviewPanelFocusOwnership {
    var panelIsKey: Bool?
    private(set) var presentedStates: [PreviewViewState] = []
    private(set) var dismissCount = 0

    var lastState: PreviewViewState? {
        presentedStates.last
    }

    var presentedStateCount: Int {
        presentedStates.count
    }

    func show(_ state: PreviewViewState, anchorRect: CGRect?) {
        presentedStates.append(state)
    }

    func update(_ state: PreviewViewState) {
        presentedStates.append(state)
    }

    func dismiss() {
        dismissCount += 1
    }

    func currentSessionPanelIsKey() -> Bool {
        panelIsKey ?? false
    }
}

@MainActor
private final class StaleTargetMonitorSpy: TargetChangeMonitoring {
    private(set) var lastEnvelope: AXMonitorCallbackEnvelope?

    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {
        lastEnvelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
    }

    func stopMonitoring() {}
}
