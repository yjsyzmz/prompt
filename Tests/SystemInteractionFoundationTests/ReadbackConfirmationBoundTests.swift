import Foundation
import XCTest

/// T-061：回读确认必须有界、只调用一次 setter、超时 fail-closed。
///
/// 真实环境的事实（T-037 已记录、T-058 的埋点在 2026-08-04 再次抓到四条
/// `replacement-stage=readback failure=writeFailed`）：Chromium 在渲染进程里
/// 异步应用辅助功能写入，setter 立刻返回成功，紧接着的回读仍是写入前的值。
/// 旧实现是「5 次固定 100ms 重试」——预算既没有单调时钟约束，也不会在目标失效
/// 时提前停止，而且比较用的是 Swift `String ==`（规范等价），不是 UTF-16 逐码元。
///
/// 本套件把 T-061 的九项条件逐条固定下来，包含任务明文要求的三条失败优先测试。
final class ReadbackConfirmationBoundTests: XCTestCase {
    // MARK: - 必须包含的三条失败优先测试

    /// (a) 延迟后最终一致：setter 之后前若干次回读不一致、deadline 内某次一致，
    /// 须报成功，且 setter 只调用一次。
    func testDelayedApplicationIsConfirmedWithASingleSetter() async {
        let probe = await ReadbackProbe.make()
        probe.host.acceptSetterWithoutApplying()
        let expected = probe.snapshot.transformedText.value
        probe.sleeper.onSleep = { [host = probe.host] sleepIndex in
            // 第二次等待之后渲染进程才真正应用了写入。
            if sleepIndex == 2 {
                host.editSegmentExternally(expected)
            }
        }

        let result = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        guard case .success = result else {
            XCTFail("a write that lands inside the budget must be confirmed")
            return
        }
        XCTAssertEqual(
            probe.host.setterAttemptCount,
            1,
            "retrying the readback must never retry the write"
        )
        let confirmedAttempts = await probe.gateway.readbackAttemptCount()
        XCTAssertEqual(
            confirmedAttempts,
            3,
            "two failed readbacks then the confirming one"
        )
        XCTAssertEqual(probe.recorder.snapshot().last?.stage, .completed)
    }

    /// (b) 直到 deadline 仍不一致：须 fail-closed 报未确认，且不得追加写入。
    func testUnconfirmedUntilDeadlineFailsClosedWithoutAnotherWrite() async {
        let probe = await ReadbackProbe.make()
        probe.host.acceptSetterWithoutApplying()
        let textBefore = probe.host.fullText

        let result = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        guard case .failure(let failure) = result else {
            XCTFail("an unconfirmed write must not be reported as success")
            return
        }
        XCTAssertEqual(
            failure,
            .writeFailed,
            "the safe fallback keeps the result copyable and claims no write"
        )
        XCTAssertEqual(
            probe.host.setterAttemptCount,
            1,
            "fail-closed means no additional write attempt"
        )
        XCTAssertEqual(probe.host.fullText, textBefore)
        let spentAttempts = await probe.gateway.readbackAttemptCount()
        XCTAssertEqual(
            spentAttempts,
            ReadbackBudget.default.maximumAttempts,
            "the whole readback budget must be spent before giving up"
        )
        XCTAssertEqual(probe.recorder.snapshot().last?.stage, .readback)
    }

    /// (c) 回读中途 session／target 失效：须立即停止回读而非等到 deadline，
    /// 报告未确认，不得追加任何写入，且剩余回读次数确实未被消耗。
    func testTargetInvalidationDuringReadbackStopsImmediately() async {
        let probe = await ReadbackProbe.make()
        probe.host.acceptSetterWithoutApplying()
        probe.sleeper.onSleep = { [host = probe.host] sleepIndex in
            if sleepIndex == 1 {
                host.invalidateElement()
            }
        }

        let result = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        guard case .failure(let failure) = result else {
            XCTFail("an unconfirmed write must not be reported as success")
            return
        }
        XCTAssertEqual(failure, .writeFailed)
        XCTAssertEqual(
            probe.host.setterAttemptCount,
            1,
            "an aborted readback must not write again"
        )

        let attempts = await probe.gateway.readbackAttemptCount()
        XCTAssertEqual(
            attempts,
            1,
            "the loop must stop at the invalidation, not keep polling"
        )
        XCTAssertLessThan(
            attempts,
            ReadbackBudget.default.maximumAttempts,
            "the remaining readback budget must be left unspent"
        )
        XCTAssertEqual(
            probe.sleeper.sleptDurations.count,
            1,
            "no further waiting is allowed once the target is invalid"
        )
        XCTAssertEqual(
            probe.recorder.snapshot().last?.stage,
            .readbackAborted,
            "an abort must stay distinguishable from a spent budget"
        )
    }

    // MARK: - (1)(2) 单调时钟与有界退避

    func testBackoffAndTotalWaitStayInsideTheDeclaredBounds() async {
        let probe = await ReadbackProbe.make()
        probe.host.acceptSetterWithoutApplying()

        _ = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        let budget = ReadbackBudget.default
        let waits = probe.sleeper.sleptDurations
        XCTAssertEqual(
            waits.count,
            budget.maximumAttempts - 1,
            "there is exactly one wait between consecutive readbacks"
        )
        for wait in waits {
            XCTAssertLessThanOrEqual(
                wait,
                budget.maximumBackoffNanoseconds,
                "no single wait may exceed the backoff cap"
            )
        }
        XCTAssertLessThanOrEqual(
            waits.reduce(0, +),
            budget.totalBudgetNanoseconds,
            "the waits together may never exceed the total budget"
        )
        XCTAssertEqual(
            waits.first,
            budget.initialBackoffNanoseconds,
            "the first wait is the declared initial backoff"
        )
    }

    /// 预算必须由**单调时钟**裁定，而不是由重试次数兜底：把次数上限抬到远高于
    /// 时间上限，循环仍须在 deadline 处停下。
    func testTheDeadlineStopsTheLoopIndependentlyOfTheAttemptCeiling() async {
        let budget = ReadbackBudget(
            maximumAttempts: 100,
            totalBudgetNanoseconds: 300_000_000,
            initialBackoffNanoseconds: 100_000_000,
            maximumBackoffNanoseconds: 100_000_000
        )
        let probe = await ReadbackProbe.make(budget: budget)
        probe.host.acceptSetterWithoutApplying()

        _ = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        let attempts = await probe.gateway.readbackAttemptCount()
        XCTAssertEqual(
            attempts,
            4,
            "three 100ms waits reach the 300ms deadline after the fourth readback"
        )
        XCTAssertLessThan(
            attempts,
            budget.maximumAttempts,
            "the monotonic deadline, not the attempt ceiling, ended this loop"
        )
        XCTAssertEqual(probe.sleeper.sleptDurations.reduce(0, +), 300_000_000)
    }

    // MARK: - (3) 逐 UTF-16 码元比较

    /// 规范等价不是相等。`String ==` 会把预组合的 `é` 与分解形式判为相等，
    /// 但那是**不同的 UTF-16 码元序列**，用它确认写入等于放宽了写入判据。
    func testCanonicallyEquivalentTextIsNotAcceptedAsConfirmation() async {
        let probe = await ReadbackProbe.make(
            fullText: "\(SyntheticAXTextHost.syntheticMarker) caf\u{00E9} r\u{00E9}sum\u{00E9}"
        )
        let expected = probe.snapshot.transformedText.value
        let decomposed = expected.decomposedStringWithCanonicalMapping

        // 前置事实：Swift 认为两者相等，UTF-16 码元序列却不同。
        XCTAssertEqual(decomposed, expected, "Swift compares canonical forms")
        XCTAssertNotEqual(
            Array(decomposed.utf16),
            Array(expected.utf16),
            "the fixture must actually differ in UTF-16 code units"
        )

        probe.host.acceptSetterWithoutApplying()
        probe.sleeper.onSleep = { [host = probe.host] sleepIndex in
            if sleepIndex == 1 {
                host.editSegmentExternally(decomposed)
            }
        }

        let result = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        guard case .failure(let failure) = result else {
            XCTFail("a normalisation difference must not count as confirmed")
            return
        }
        XCTAssertEqual(failure, .writeFailed)
    }

    // MARK: - (4)(5)(6) 写入约束

    /// 选区路径的重试只能重复回读，绝不允许换用整段 setter 作为「重试」手段。
    func testSelectedModeNeverFallsBackToTheWholeFieldSetter() async {
        let probe = await ReadbackProbe.make(host: .selectionFixture())
        probe.host.acceptSetterWithoutApplying()

        _ = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        XCTAssertEqual(probe.host.selectedSetterAttemptCount, 1)
        XCTAssertEqual(
            probe.host.wholeFieldSetterAttemptCount,
            0,
            "substituting another setter would widen the approved write surface"
        )
        XCTAssertEqual(probe.host.setterAttemptCount, 1)
    }

    /// setter 返回成功不等于最终成功——唯一的成功判据是回读一致。
    func testSetterSuccessAloneIsNeverReportedAsSuccess() async {
        let probe = await ReadbackProbe.make()
        probe.host.acceptSetterWithoutApplying()

        let result = await probe.gateway.replaceAfterAuthoritativeValidation(
            probe.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        XCTAssertEqual(
            probe.host.setterAttemptCount,
            1,
            "the setter did run and did report success"
        )
        guard case .failure = result else {
            XCTFail("a reported-but-unapplied write must fail closed")
            return
        }
    }

    // MARK: - (8) 安全后备动作

    func testUnconfirmedWriteOffersACopyableResultAndClaimsNoWrite() {
        let presentation = DomainFailureMapper().presentation(for: .writeFailed)

        XCTAssertTrue(presentation.isFailClosed)
        XCTAssertEqual(presentation.safeNextActions, [.copyResult])
        XCTAssertFalse(
            presentation.safeNextActions.contains(.retry),
            "an unconfirmed write must not offer to write again automatically"
        )
    }

    // MARK: - (9) 隐私边界（沿用 T-052）

    func testReadbackDiagnosticsCarryNoContentOrDigits() async {
        let marker = SyntheticAXTextHost.syntheticMarker
        var descriptions: [String] = []

        let exhausted = await ReadbackProbe.make()
        exhausted.host.acceptSetterWithoutApplying()
        _ = await exhausted.gateway.replaceAfterAuthoritativeValidation(
            exhausted.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )
        descriptions += exhausted.recorder.snapshot().map { String(describing: $0) }

        let aborted = await ReadbackProbe.make()
        aborted.host.acceptSetterWithoutApplying()
        aborted.sleeper.onSleep = { [host = aborted.host] sleepIndex in
            if sleepIndex == 1 {
                host.invalidateElement()
            }
        }
        _ = await aborted.gateway.replaceAfterAuthoritativeValidation(
            aborted.snapshot,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )
        descriptions += aborted.recorder.snapshot().map { String(describing: $0) }

        XCTAssertFalse(descriptions.isEmpty)
        for description in descriptions {
            XCTAssertFalse(description.contains(marker))
            XCTAssertFalse(description.contains("文字"))
            XCTAssertNil(
                description.rangeOfCharacter(from: .decimalDigits),
                "FR-013: readback diagnostics must expose no measure of content"
            )
        }
    }
}

// MARK: - Probe

private struct ReadbackProbe {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let recorder: ReadbackStageRecorderSpy
    let clock: FakeMonotonicClock
    let sleeper: ReadbackSleeperSpy
    let snapshot: AXWriteSnapshot

    static func make(
        host: SyntheticAXTextHost = .wholeFieldFixture(),
        fullText: String? = nil,
        budget: ReadbackBudget = .default
    ) async -> ReadbackProbe {
        if let fullText {
            host.replaceFullTextForTesting(fullText)
        }
        let recorder = ReadbackStageRecorderSpy()
        let clock = FakeMonotonicClock()
        let sleeper = ReadbackSleeperSpy(clock: clock)
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host,
            diagnostics: recorder,
            clock: clock,
            sleeper: sleeper,
            readbackBudget: budget
        )
        guard
            case .success(let captured) = await gateway.capture(
                sessionID: InteractionSessionID()
            ),
            let pid = await gateway.authoritativePID(for: captured.targetHandle)
        else {
            fatalError("the fixture must capture successfully")
        }
        return ReadbackProbe(
            host: host,
            gateway: gateway,
            recorder: recorder,
            clock: clock,
            sleeper: sleeper,
            snapshot: AXWriteSnapshot(
                targetHandle: captured.targetHandle,
                pid: pid,
                captureMode: captured.captureMode,
                originalText: captured.sourceText,
                transformedText: DeterministicTransformer()
                    .transform(captured.sourceText)
            )
        )
    }
}

// MARK: - Doubles

/// A monotonic clock that only ever moves forward, and only when something
/// actually waited. A wall-clock adjustment has no representation here, which is
/// the point: the budget must not be expressible in wall-clock terms.
private final class FakeMonotonicClock: MonotonicClockReading, @unchecked Sendable {
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

private final class ReadbackSleeperSpy: MonotonicSleeping, @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [UInt64] = []
    private let clock: FakeMonotonicClock

    /// Called with the 1-based index of the wait that just happened, so a test
    /// can make the world change *between* readbacks without real time passing.
    var onSleep: ((Int) -> Void)?

    init(clock: FakeMonotonicClock) {
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

private final class ReadbackStageRecorderSpy:
    ReplacementDiagnosticsRecording, @unchecked Sendable
{
    private let lock = NSLock()
    private var reports: [ReplacementStageReport] = []

    func record(_ report: ReplacementStageReport) {
        lock.lock()
        defer { lock.unlock() }
        reports.append(report)
    }

    func snapshot() -> [ReplacementStageReport] {
        lock.lock()
        defer { lock.unlock() }
        return reports
    }
}
