import Foundation
import XCTest

/// T-065 第二轮：会话代际隔离与恢复动作的单飞门禁。
///
/// 依 Solar 对 `0fd26a1` 的 REVIEW：
///
/// - MUST 1：`InteractionSessionCoordinator` 的 session ID 校验只保护 UI 状态，它发生在
///   `GatewaySessionTextTarget` **已经处理完结果之后**。旧任务返回时仍会无条件写
///   `recoveryContext`／`lastRecoveryFailure`，因此会把已结束会话的敏感恢复上下文放
///   回来，或污染／清除新会话的状态。违反 `plan.md` 第 55 行与第 387 行。
/// - MUST 2：`recoverOriginal` 启动任务后仍停在 `.recoverable` 且不检查已有在途任务，
///   连点两次会产生两个恢复写入，句柄还会被后一个覆盖。
///
/// 全部用确定性握手：sleeper 替身在回读第一轮把操作**卡住**，测试在 `MainActor` 上
/// 完成会话切换，再放行并等待在途任务，因此断言不依赖调度顺序。
@MainActor
final class SessionGenerationIsolationTests: XCTestCase {
    // MARK: - MUST 1：旧任务不得写回共享恢复状态

    /// 旧 replacement 在 `endSession()` 之后返回成功：不得把敏感恢复上下文放回。
    func testOldReplacementSucceedingAfterSessionEndLeavesNoRecoveryContext() async {
        let probe = await AdapterProbe.make()
        probe.arrangeWriteThatSucceedsOnTheSecondReadback()

        let work = probe.startReplace()
        await probe.waitUntilReadbackIsHeld()
        probe.target.endSession()
        probe.releaseReadback()
        _ = await work.value

        let hasContext = await probe.target.validateForRecovery(probe.content)
        XCTAssertFalse(
            hasContext,
            "会话已结束，旧写入的恢复上下文不得被放回（plan.md 第 387 行）"
        )
    }

    /// 旧 replacement 在**新会话开始后**返回成功：不得把旧上下文注入新会话。
    func testOldReplacementSucceedingAfterNewSessionDoesNotInjectItsContext() async {
        let probe = await AdapterProbe.make()
        probe.arrangeWriteThatSucceedsOnTheSecondReadback()

        let work = probe.startReplace()
        await probe.waitUntilReadbackIsHeld()
        probe.target.beginSession(
            targetHandle: probe.captured.targetHandle,
            pid: probe.pid
        )
        probe.releaseReadback()
        _ = await work.value

        let hasContext = await probe.target.validateForRecovery(probe.content)
        XCTAssertFalse(
            hasContext,
            "新会话不得继承旧会话的恢复上下文（plan.md 第 55 行）"
        )
    }

    /// 旧 restore 在新会话已建立之后返回失败：不得把旧失败写进新会话。
    func testOldRestoreReturningAfterNewSessionDoesNotPolluteItsFailure() async {
        let probe = await AdapterProbe.make()

        // 先在旧会话里完成一次成功替换，建立恢复上下文。
        let replaced = await probe.target.replace(probe.content)
        guard case .success = replaced else {
            XCTFail("恢复隔离测试需要先有一次成功替换")
            return
        }

        probe.arrangeRestoreThatIsHeldOnItsFirstReadback()
        let work = probe.startRestore()
        await probe.waitUntilReadbackIsHeld()
        // 会话切换，并让旧 restore 注定失败。
        probe.target.endSession()
        probe.target.beginSession(
            targetHandle: probe.captured.targetHandle,
            pid: probe.pid
        )
        probe.host.invalidateElement()
        probe.releaseReadback()
        _ = await work.value

        XCTAssertNil(
            probe.target.lastRecoveryFailure,
            "旧 restore 的失败不得写进新会话的状态（plan.md 第 55 行）"
        )
    }

    // MARK: - MUST 2：至多一个在途恢复

    /// 连点两次「恢复原文」只允许产生一次 restore 写入。
    ///
    /// 用握手把第一次恢复卡在它的第一轮回读上，**保证**第二次点击发生在第一次仍在
    /// 途时——否则第一次可能已经完成并清空恢复上下文，第二次自然变成空操作，测试
    /// 就会因调度顺序而假通过。
    func testRepeatedRecoveryActionPerformsExactlyOneRestore() async {
        let env = await RecoveryEnvironment.make()
        await env.reachRecoverable()
        let settersAfterReplacement = env.host.setterAttemptCount
        env.holdFirstRestoreReadback()

        env.controller.handle(.restoreOriginal)
        let firstAttempt = env.controller.recoverWork
        await env.waitUntilReadbackIsHeld()
        env.controller.handle(.restoreOriginal)
        let secondAttempt = env.controller.recoverWork
        env.releaseReadback()
        await firstAttempt?.value
        await secondAttempt?.value

        XCTAssertEqual(
            env.host.setterAttemptCount - settersAfterReplacement,
            1,
            "重复的恢复动作只允许一次 restore／setter"
        )
    }
}

// MARK: - Adapter probe（MUST 1）

/// 直接驱动 `GatewaySessionTextTarget`，因为被测行为就在这一层：协调器的
/// session ID 校验发生在它之后，保护不到它。
@MainActor
private final class AdapterProbe {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let target: GatewaySessionTextTarget
    let sleeper: IsolationSleeperSpy
    let captured: AXCapturedTarget
    let pid: Int32
    let content: SessionContent

    private let held = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    private init(
        host: SyntheticAXTextHost,
        gateway: AccessibilityGateway,
        target: GatewaySessionTextTarget,
        sleeper: IsolationSleeperSpy,
        captured: AXCapturedTarget,
        pid: Int32,
        content: SessionContent
    ) {
        self.host = host
        self.gateway = gateway
        self.target = target
        self.sleeper = sleeper
        self.captured = captured
        self.pid = pid
        self.content = content
    }

    static func make() async -> AdapterProbe {
        let host = SyntheticAXTextHost.wholeFieldFixture()
        let clock = IsolationClockFake()
        let sleeper = IsolationSleeperSpy(clock: clock)
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host,
            clock: clock,
            sleeper: sleeper
        )
        guard
            case .success(let captured) = await gateway.capture(
                sessionID: InteractionSessionID()
            ),
            let pid = await gateway.authoritativePID(for: captured.targetHandle)
        else {
            fatalError("夹具必须能成功捕获")
        }
        let target = GatewaySessionTextTarget(gateway: gateway)
        target.beginSession(targetHandle: captured.targetHandle, pid: pid)
        return AdapterProbe(
            host: host,
            gateway: gateway,
            target: target,
            sleeper: sleeper,
            captured: captured,
            pid: pid,
            content: SessionContent(
                source: captured.sourceText,
                transformed: DeterministicTransformer()
                    .transform(captured.sourceText),
                mode: captured.captureMode
            )
        )
    }

    /// setter 先不落地，第一轮等待被卡住；放行时补上写入，于是第二轮回读一致。
    func arrangeWriteThatSucceedsOnTheSecondReadback() {
        host.acceptSetterWithoutApplying()
        let expected = content.transformed.value
        holdFirstReadback { [host] in
            host.editSegmentExternally(expected)
        }
    }

    /// restore 的第一轮回读被卡住，放行后由调用方决定它成功还是失败。
    func arrangeRestoreThatIsHeldOnItsFirstReadback() {
        host.acceptSetterWithoutApplying()
        holdFirstReadback {}
    }

    private func holdFirstReadback(_ onHold: @escaping @Sendable () -> Void) {
        let held = self.held
        let release = self.release
        var alreadyHeld = false
        sleeper.onSleep = { _ in
            guard !alreadyHeld else {
                return
            }
            alreadyHeld = true
            onHold()
            held.signal()
            release.wait()
        }
    }

    func startReplace() -> Task<Result<Void, DomainFailure>, Never> {
        Task { [target, content] in
            await target.replace(content)
        }
    }

    func startRestore() -> Task<Bool, Never> {
        Task { [target, content] in
            await target.restore(content)
        }
    }

    func waitUntilReadbackIsHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let held = self.held
            DispatchQueue.global().async {
                held.wait()
                continuation.resume()
            }
        }
    }

    func releaseReadback() {
        release.signal()
    }
}

// MARK: - Recovery environment（MUST 2）

@MainActor
private final class RecoveryEnvironment {
    let host: SyntheticAXTextHost
    let controller: AppLifecycleController
    let hotKey: IsolationHotKeyClientFake
    let sleeper: IsolationSleeperSpy

    private let held = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    private init(
        host: SyntheticAXTextHost,
        controller: AppLifecycleController,
        hotKey: IsolationHotKeyClientFake,
        sleeper: IsolationSleeperSpy
    ) {
        self.host = host
        self.controller = controller
        self.hotKey = hotKey
        self.sleeper = sleeper
    }

    static func make() async -> RecoveryEnvironment {
        let host = SyntheticAXTextHost.wholeFieldFixture()
        let clock = IsolationClockFake()
        let sleeper = IsolationSleeperSpy(clock: clock)
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host,
            clock: clock,
            sleeper: sleeper
        )
        let hotKey = IsolationHotKeyClientFake()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: IsolationPermissionCheckerFake(),
            settingsOpener: IsolationSettingsOpenerFake(),
            secureInputChecker: IsolationSecureInputCheckerFake(),
            pasteboard: IsolationPasteboardSpy(),
            gateway: gateway,
            targetMonitor: IsolationTargetMonitorSpy(),
            presenter: IsolationPresenterSpy()
        )
        _ = controller.start()
        return RecoveryEnvironment(
            host: host,
            controller: controller,
            hotKey: hotKey,
            sleeper: sleeper
        )
    }

    func reachRecoverable() async {
        hotKey.press()
        await controller.captureWork?.value
        controller.handle(.confirmReplacement)
        await controller.applyWork?.value
    }

    /// 让接下来第一次恢复写入的回读停在第一轮等待上。恢复的 setter 不落地，因此
    /// 一定会进入回读等待。
    func holdFirstRestoreReadback() {
        host.acceptSetterWithoutApplying()
        let held = self.held
        let release = self.release
        var alreadyHeld = false
        sleeper.onSleep = { _ in
            guard !alreadyHeld else {
                return
            }
            alreadyHeld = true
            held.signal()
            release.wait()
        }
    }

    func waitUntilReadbackIsHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let held = self.held
            DispatchQueue.global().async {
                held.wait()
                continuation.resume()
            }
        }
    }

    func releaseReadback() {
        release.signal()
    }
}

// MARK: - Doubles

private final class IsolationClockFake: MonotonicClockReading, @unchecked Sendable {
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

private final class IsolationSleeperSpy: MonotonicSleeping, @unchecked Sendable {
    private let clock: IsolationClockFake
    private let lock = NSLock()
    private var hook: ((Int) -> Void)?
    private var count = 0

    var onSleep: ((Int) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return hook
        }
        set {
            lock.lock()
            hook = newValue
            lock.unlock()
        }
    }

    init(clock: IsolationClockFake) {
        self.clock = clock
    }

    func sleep(nanoseconds: UInt64) {
        lock.lock()
        count += 1
        let index = count
        let hook = self.hook
        lock.unlock()
        clock.advance(by: nanoseconds)
        hook?(index)
    }
}

@MainActor
private final class IsolationHotKeyClientFake: HotKeySystemClient {
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
private final class IsolationPermissionCheckerFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class IsolationSettingsOpenerFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class IsolationSecureInputCheckerFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class IsolationPasteboardSpy: PasteboardAccessing {
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
private final class IsolationPresenterSpy: PreviewPresenting {
    func show(_ state: PreviewViewState, anchorRect: CGRect?) {}
    func update(_ state: PreviewViewState) {}
    func dismiss() {}
}

@MainActor
private final class IsolationTargetMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
