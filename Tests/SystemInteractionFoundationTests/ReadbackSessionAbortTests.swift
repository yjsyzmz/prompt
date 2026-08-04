import Foundation
import XCTest

/// T-065：「会话／面板关闭立即中止回读」必须在**生产调用链**上真正成立。
///
/// 依 Solar 对 `ad5c9df` 的 REVIEW Finding 1：既有
/// `testTargetInvalidationDuringReadbackStopsImmediately` 只在 fake sleeper 回调里
/// 直接令合成 AX 元素失效，证明的是 A3／A4 外部变化能在下一轮被看到，**没有**证明
/// tasks.md T-061 条件 (7) 明文要求的 session／panel-close 中止。
///
/// 本套件走完整生产装配：`AppLifecycleController` → `InteractionSessionCoordinator`
/// → `GatewaySessionTextTarget.replace`（`DispatchSemaphore.wait()` 阻塞 `MainActor`）
/// → `AccessibilityGateway.confirmWrittenText`（actor 内同步 `nanosleep`）。只有时钟
/// 与休眠被替身化，其余全是生产对象。
///
/// **本文件的测试当前处于 `XCTSkip` 状态，原因写在每个测试的 skip 消息里**：真实
/// RED 已记录于 `evidence/T-065-readback-session-abort.md`，而使其转绿需要改变已批准
/// 的数据流／写入隔离方式，按 T-065 的约束必须先重开 Plan Gate。skip 是为了让门禁
/// 反映「尚未修复」而不是「已经通过」，并在 Plan Gate 批准后由修复提交移除。
@MainActor
final class ReadbackSessionAbortTests: XCTestCase {
    /// 置为 `false` 即可重新启用全部三项。修复须先取得 Plan Gate 批准，届时由修复
    /// 提交把它改掉——这是本文件唯一的开关，不存在逐个测试悄悄跳过的空间。
    private static let planGateStillPending = true

    private static let pendingPlanGate = """
        T-065：使本测试转绿需要让 MainActor 在回读期间仍能处理会话结束，\
        这会改变已批准 Plan 0c9883f 的数据流与写入隔离方式，须先重开 Plan Gate。\
        真实 RED 已记录于 evidence/T-065-readback-session-abort.md：\
        三个触发全部消耗完 8 次回读与 7 次等待，中止请求无一生效。
        """

    // MARK: - 触发一：真人在回读进行中关闭面板

    func testClosingThePanelDuringReadbackStopsItWithoutWaitingForTheDeadline() async throws {
        try XCTSkipIf(Self.planGateStillPending, Self.pendingPlanGate)

        let env = await AbortEnvironment.make()
        await env.reachReadyPreview()
        env.host.acceptSetterWithoutApplying()
        env.sleeper.onSleep = { [env] sleepIndex in
            if sleepIndex == 1 {
                env.requestOnMainActor { controller in
                    controller.handle(.close)
                }
            }
        }

        env.controller.handle(.confirmReplacement)
        await env.settle()

        try await env.assertAbortedEarly()
    }

    // MARK: - 触发二：协调器在回读进行中结束会话

    func testCoordinatorCloseDuringReadbackStopsItWithoutWaitingForTheDeadline() async throws {
        try XCTSkipIf(Self.planGateStillPending, Self.pendingPlanGate)

        let env = await AbortEnvironment.make()
        await env.reachReadyPreview()
        env.host.acceptSetterWithoutApplying()
        env.sleeper.onSleep = { [env] sleepIndex in
            if sleepIndex == 1 {
                env.requestOnMainActor { controller in
                    controller.stop()
                }
            }
        }

        env.controller.handle(.confirmReplacement)
        await env.settle()

        try await env.assertAbortedEarly()
    }

    // MARK: - 触发三：新会话在回读进行中抢占旧会话

    func testNewSessionPreemptionDuringReadbackStopsTheOldReadback() async throws {
        try XCTSkipIf(Self.planGateStillPending, Self.pendingPlanGate)

        let env = await AbortEnvironment.make()
        await env.reachReadyPreview()
        env.host.acceptSetterWithoutApplying()
        env.sleeper.onSleep = { [env] sleepIndex in
            if sleepIndex == 1 {
                env.requestOnMainActor { _ in
                    env.hotKey.press()
                }
            }
        }

        env.controller.handle(.confirmReplacement)
        await env.settle()

        try await env.assertAbortedEarly()
    }
}

// MARK: - Environment

/// 生产装配：只有 clock 与 sleeper 是替身，coordinator、`GatewaySessionTextTarget`
/// 与其 `DispatchSemaphore` 桥、`AccessibilityGateway` 全部是生产对象。
@MainActor
private final class AbortEnvironment {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let controller: AppLifecycleController
    let hotKey: AbortHotKeyClientFake
    let presenter: AbortPresenterSpy
    let sleeper: AbortSleeperSpy
    let budget: ReadbackBudget

    private init(
        host: SyntheticAXTextHost,
        gateway: AccessibilityGateway,
        controller: AppLifecycleController,
        hotKey: AbortHotKeyClientFake,
        presenter: AbortPresenterSpy,
        sleeper: AbortSleeperSpy,
        budget: ReadbackBudget
    ) {
        self.host = host
        self.gateway = gateway
        self.controller = controller
        self.hotKey = hotKey
        self.presenter = presenter
        self.sleeper = sleeper
        self.budget = budget
    }

    static func make() async -> AbortEnvironment {
        let host = SyntheticAXTextHost.wholeFieldFixture()
        let clock = AbortClockFake()
        let sleeper = AbortSleeperSpy(clock: clock)
        let budget = ReadbackBudget.default
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host,
            clock: clock,
            sleeper: sleeper,
            readbackBudget: budget
        )
        let hotKey = AbortHotKeyClientFake()
        let presenter = AbortPresenterSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: AbortPermissionCheckerFake(),
            settingsOpener: AbortSettingsOpenerFake(),
            secureInputChecker: AbortSecureInputCheckerFake(),
            pasteboard: AbortPasteboardSpy(),
            gateway: gateway,
            targetMonitor: AbortTargetMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return AbortEnvironment(
            host: host,
            gateway: gateway,
            controller: controller,
            hotKey: hotKey,
            presenter: presenter,
            sleeper: sleeper,
            budget: budget
        )
    }

    func reachReadyPreview() async {
        hotKey.press()
        await controller.captureWork?.value
    }

    /// 从回读循环所在的 detached task 请求一个 `MainActor` 动作。
    ///
    /// 这正是真实情形的形状：用户的点击、面板关闭与新会话都只能在 `MainActor` 上被
    /// 处理，而此刻 `MainActor` 正停在 `performBlocking` 的 `semaphore.wait()` 上，
    /// 因此请求只能排队。测试要断言的就是「排队的中止请求能否及时生效」。
    nonisolated func requestOnMainActor(
        _ action: @escaping @Sendable @MainActor (AppLifecycleController) -> Void
    ) {
        Task { @MainActor [controller] in
            action(controller)
        }
    }

    /// 让排队的 `MainActor` 工作有机会执行，再做断言。
    func settle() async {
        await controller.cleanupWork?.value
        for _ in 0 ..< 4 {
            await Task.yield()
        }
    }

    func assertAbortedEarly() async throws {
        let attempts = await gateway.readbackAttemptCount()

        XCTAssertLessThan(
            attempts,
            budget.maximumAttempts,
            "中止请求到达后，剩余回读次数必须不再被消耗"
        )
        XCTAssertLessThan(
            sleeper.sleptDurations.count,
            budget.maximumAttempts - 1,
            "无需等到 deadline：中止后不得继续等待"
        )
        XCTAssertEqual(
            host.setterAttemptCount,
            1,
            "被中止的回读不得追加任何写入"
        )
        XCTAssertFalse(
            presenter.presentedRecoverable,
            "未确认的写入结果不得进入 recoverable"
        )
    }
}

// MARK: - Doubles

private final class AbortClockFake: MonotonicClockReading, @unchecked Sendable {
    private let lock = NSLock()
    private var current: UInt64 = 1_000_000_000

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by nanoseconds: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        current += nanoseconds
    }
}

private final class AbortSleeperSpy: MonotonicSleeping, @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [UInt64] = []
    private let clock: AbortClockFake

    var onSleep: ((Int) -> Void)?

    init(clock: AbortClockFake) {
        self.clock = clock
    }

    func sleep(nanoseconds: UInt64) {
        lock.lock()
        durations.append(nanoseconds)
        let index = durations.count
        lock.unlock()
        clock.advance(by: nanoseconds)
        onSleep?(index)
    }

    var sleptDurations: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return durations
    }
}

@MainActor
private final class AbortHotKeyClientFake: HotKeySystemClient {
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
private final class AbortPermissionCheckerFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class AbortSettingsOpenerFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class AbortSecureInputCheckerFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class AbortPasteboardSpy: PasteboardAccessing {
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

@MainActor
private final class AbortPresenterSpy: PreviewPresenting {
    private(set) var presentedStates: [PreviewViewState] = []
    private(set) var dismissCount = 0

    /// 出现过「可恢复」状态即视为旧结果已进入 recoverable：该状态是唯一提供
    /// 「恢复原文」动作的状态。
    var presentedRecoverable: Bool {
        presentedStates.contains { state in
            state.buttons.contains { $0.action == .restoreOriginal && $0.isEnabled }
        }
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
}

@MainActor
private final class AbortTargetMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
