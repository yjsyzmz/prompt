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
/// → `GatewaySessionTextTarget.replace`（`plan.md` 第 129–136 行批准的 `async` 契约）
/// → `AccessibilityGateway.confirmWrittenText`。只有时钟与休眠被替身化。
///
/// 依 REVIEW（`005ca4c`）Finding 3，三项测试使用**确定性握手**而不是 `Task.yield()`
/// 猜调度，逐步证明：(a) 第一轮 sleep 已进入；(b) 中止已在 `MainActor` 上实际处理
/// 完毕；(c) 才放行后续回读；(d) 等生产任务结束后再断言。
@MainActor
final class ReadbackSessionAbortTests: XCTestCase {
    // MARK: - 触发一：真人在回读进行中关闭面板

    func testClosingThePanelDuringReadbackStopsItWithoutWaitingForTheDeadline() async {
        let env = await AbortEnvironment.make()
        await env.assertAbortStopsReadback { controller in
            controller.handle(.close)
        }
    }

    // MARK: - 触发二：协调器在回读进行中结束会话

    func testCoordinatorCloseDuringReadbackStopsItWithoutWaitingForTheDeadline() async {
        let env = await AbortEnvironment.make()
        await env.assertAbortStopsReadback { controller in
            controller.stop()
        }
    }

    // MARK: - 触发三：新会话在回读进行中抢占旧会话

    func testNewSessionPreemptionDuringReadbackStopsTheOldReadback() async {
        let env = await AbortEnvironment.make()
        await env.assertAbortStopsReadback { [hotKey = env.hotKey] _ in
            hotKey.press()
        }
    }

    // MARK: - 取消之后不得让旧结果进入 recoverable

    /// `plan.md` 第 55 行：异步结果返回时必须再次匹配当前 session ID。被取消的写入
    /// 即便随后完成，也不得把旧 session 的结果送进 `recoverable`。
    func testCancelledWriteNeverReachesRecoverableEvenIfItLaterSucceeds() async {
        let env = await AbortEnvironment.make()
        await env.reachReadyPreview()
        // 写入本身会成功，但会话在回读期间结束。
        env.host.acceptSetterWithoutApplying()
        let expected = env.snapshotTransformedText
        env.sleeper.onSleep = { [host = env.host] index in
            if index == 1 {
                host.editSegmentExternally(expected)
            }
        }

        await env.assertAbortStopsReadback(configureSleeper: false) { controller in
            controller.handle(.close)
        }

        XCTAssertFalse(
            env.presenter.presentedRecoverable,
            "旧 session 的写入结果不得进入 recoverable"
        )
    }

    // MARK: - T-067 Finding 2：recovery 回读必须走生产 bridge 才能被会话取消

    /// W4：面板关闭中止恢复回读。现有
    /// `testWholeFieldRecoveryTargetLossAbortsReadbackWithoutSpendingBudget`
    /// 只在 sleeper 里把元素身份关掉，覆盖不了 session cancellation。
    func testWholeFieldRecoveryReadbackStopsWhenPanelCloses() async {
        let env = await AbortEnvironment.makeForRecovery(.wholeFieldW4)
        await env.assertRecoveryAbortStopsReadback { controller in
            controller.handle(.close)
        }
    }

    /// R1：`coordinator.stop()` 中止恢复回读。
    func testSelectedR1RecoveryReadbackStopsWhenCoordinatorStops() async {
        let env = await AbortEnvironment.makeForRecovery(.selectedR1)
        await env.assertRecoveryAbortStopsReadback { controller in
            controller.stop()
        }
    }

    /// R2：新会话抢占中止恢复回读，且旧结果不得写进新会话。
    func testSelectedR2RecoveryReadbackStopsWhenNewSessionPreempts() async {
        let env = await AbortEnvironment.makeForRecovery(.selectedR2)
        await env.assertRecoveryAbortStopsReadback { [hotKey = env.hotKey] _ in
            hotKey.press()
        }
    }
}

// MARK: - Environment

/// 生产装配：只有 clock 与 sleeper 是替身，coordinator、`GatewaySessionTextTarget`
/// 与 `AccessibilityGateway` 全部是生产对象。
@MainActor
private final class AbortEnvironment {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let controller: AppLifecycleController
    let hotKey: AbortHotKeyClientFake
    let presenter: AbortPresenterSpy
    let sleeper: AbortSleeperSpy
    let budget: ReadbackBudget
    private let collapseSelectionAfterReplacement: Bool
    private var capturedOriginalSegment = ""

    /// 第一轮 sleep 已进入回读循环。
    private let sleepEntered = DispatchSemaphore(value: 0)
    /// 中止动作已在 `MainActor` 上处理完毕，回读可以继续。
    private let abortCompleted = DispatchSemaphore(value: 0)

    private init(
        host: SyntheticAXTextHost,
        gateway: AccessibilityGateway,
        controller: AppLifecycleController,
        hotKey: AbortHotKeyClientFake,
        presenter: AbortPresenterSpy,
        sleeper: AbortSleeperSpy,
        budget: ReadbackBudget,
        collapseSelectionAfterReplacement: Bool
    ) {
        self.host = host
        self.gateway = gateway
        self.controller = controller
        self.hotKey = hotKey
        self.presenter = presenter
        self.sleeper = sleeper
        self.budget = budget
        self.collapseSelectionAfterReplacement = collapseSelectionAfterReplacement
    }

    enum RecoveryPath {
        case wholeFieldW4
        case selectedR1
        case selectedR2
    }

    static func make() async -> AbortEnvironment {
        await make(host: SyntheticAXTextHost.wholeFieldFixture())
    }

    static func makeForRecovery(_ path: RecoveryPath) async -> AbortEnvironment {
        switch path {
        case .wholeFieldW4:
            return await make(host: .wholeFieldFixture())
        case .selectedR1:
            return await make(host: .selectionFixture())
        case .selectedR2:
            return await make(
                host: .selectionFixture(),
                collapseSelectionAfterReplacement: true
            )
        }
    }

    private static func make(
        host: SyntheticAXTextHost,
        collapseSelectionAfterReplacement: Bool = false
    ) async -> AbortEnvironment {
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
            budget: budget,
            collapseSelectionAfterReplacement: collapseSelectionAfterReplacement
        )
    }

    func reachReadyPreview() async {
        hotKey.press()
        await controller.captureWork?.value
    }

    /// 预览就绪时展示的结果文字，用于让夹具在回读中途「补上」写入。
    var snapshotTransformedText: String {
        presenter.presentedStates.compactMap(\.resultText).last ?? ""
    }

    /// 完整的确定性握手：确认替换 → 等第一轮 sleep 进入 → 在 `MainActor` 上执行中止
    /// → 放行回读 → 等生产任务结束 → 断言。
    ///
    /// 中止动作能在这里被执行本身就是被测行为：`MainActor` 若仍被 semaphore 占住，
    /// 这一行根本轮不到运行。
    func assertAbortStopsReadback(
        configureSleeper: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line,
        abort: @escaping @MainActor (AppLifecycleController) -> Void
    ) async {
        if configureSleeper {
            await reachReadyPreview()
            host.acceptSetterWithoutApplying()
        }
        installHandshake()

        controller.handle(.confirmReplacement)
        // 取消会把 coordinator 的句柄清空，所以先抓住在途任务再中止。
        let inFlight = controller.applyWork
        XCTAssertNotNil(inFlight, "确认替换必须启动一个可取消的在途任务", file: file, line: line)

        await waitFor(sleepEntered)          // (a)
        abort(controller)                    // (b)
        abortCompleted.signal()              // (c)
        await inFlight?.value                // (d)

        let attempts = await gateway.readbackAttemptCount()
        XCTAssertLessThan(
            attempts,
            budget.maximumAttempts,
            "中止请求到达后，剩余回读次数必须不再被消耗",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            sleeper.sleptDurations.count,
            budget.maximumAttempts - 1,
            "无需等到 deadline：中止后不得继续等待",
            file: file,
            line: line
        )
        XCTAssertEqual(
            host.setterAttemptCount,
            1,
            "被中止的回读不得追加任何写入",
            file: file,
            line: line
        )
        XCTAssertFalse(
            presenter.presentedRecoverable,
            "未确认的写入结果不得进入 recoverable",
            file: file,
            line: line
        )
    }

    func reachRecoverable() async {
        await reachReadyPreview()
        capturedOriginalSegment = host.selectedSegment
        controller.handle(.confirmReplacement)
        await controller.applyWork?.value
        if collapseSelectionAfterReplacement {
            host.collapseSelectionAfterWrite()
        }
        XCTAssertTrue(
            presenter.presentedRecoverable,
            "恢复回读测试必须从 recoverable 起步"
        )
    }

    /// 对标 `assertAbortStopsReadback`，但走 `restoreOriginal` / `recoverWork`。
    /// 第一轮恢复 sleep 期间把原文补上，证明即便回读随后会成功，取消后的结果
    /// 也不得写回 recoverable 或新会话。
    func assertRecoveryAbortStopsReadback(
        file: StaticString = #filePath,
        line: UInt = #line,
        abort: @escaping @MainActor (AppLifecycleController) -> Void
    ) async {
        await reachRecoverable()
        let settersAfterReplacement = host.setterAttemptCount
        let selectedAfterReplacement = host.selectedSetterAttemptCount
        let wholeAfterReplacement = host.wholeFieldSetterAttemptCount
        let statesBeforeAbort = presenter.presentedStates.count
        host.acceptSetterWithoutApplying()
        let original = capturedOriginalSegment
        sleeper.onSleep = { [host] index in
            if index == 1 {
                host.editSegmentExternally(original)
            }
        }
        installHandshake()

        let attemptsBeforeRecovery = await gateway.readbackAttemptCount()
        let sleepsBeforeRecovery = sleeper.sleptDurations.count

        controller.handle(.restoreOriginal)
        let inFlight = controller.recoverWork
        XCTAssertNotNil(inFlight, "恢复原文必须启动一个可取消的在途任务", file: file, line: line)

        await waitFor(sleepEntered)
        abort(controller)
        abortCompleted.signal()
        await inFlight?.value

        let attempts = await gateway.readbackAttemptCount()
        XCTAssertEqual(
            attempts - attemptsBeforeRecovery,
            1,
            "中止后 recovery 回读增量必须恰好为 1：第一轮未确认后立即停止，不得再读",
            file: file,
            line: line
        )
        XCTAssertEqual(
            sleeper.sleptDurations.count - sleepsBeforeRecovery,
            1,
            "中止后 recovery sleep 增量必须恰好为 1：不得再等待",
            file: file,
            line: line
        )
        XCTAssertEqual(
            host.setterAttemptCount - settersAfterReplacement,
            1,
            "被中止的恢复回读不得追加任何写入",
            file: file,
            line: line
        )
        if collapseSelectionAfterReplacement {
            XCTAssertEqual(
                host.wholeFieldSetterAttemptCount - wholeAfterReplacement,
                1,
                "R2 恢复必须走 whole-field setter",
                file: file,
                line: line
            )
            XCTAssertEqual(
                host.selectedSetterAttemptCount,
                selectedAfterReplacement,
                "R2 恢复不得改用 selected setter",
                file: file,
                line: line
            )
        }
        let statesAfterAbort = Array(presenter.presentedStates.dropFirst(statesBeforeAbort))
        XCTAssertFalse(
            statesAfterAbort.contains { state in
                state.buttons.contains { $0.action == .restoreOriginal && $0.isEnabled }
            },
            "旧 recovery 结果不得写回 recoverable",
            file: file,
            line: line
        )
        XCTAssertFalse(
            statesAfterAbort.contains { state in
                state.message == "目标内容已经变化，无法直接恢复。"
            },
            "旧 recovery 失败也不得写进新会话或当前面板",
            file: file,
            line: line
        )
    }

    /// 让第一轮 sleep 在回读循环里停住，直到 `MainActor` 完成中止。
    private func installHandshake() {
        let entered = sleepEntered
        let resume = abortCompleted
        let existing = sleeper.onSleep
        sleeper.onSleep = { index in
            existing?(index)
            if index == 1 {
                entered.signal()
                resume.wait()
            }
        }
    }

    /// 在不占住 `MainActor` 的前提下等待一个信号量。
    private func waitFor(_ semaphore: DispatchSemaphore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                semaphore.wait()
                continuation.resume()
            }
        }
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

    /// 出现过提供「恢复原文」动作的状态，即视为旧结果已进入 recoverable。
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
