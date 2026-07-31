import Foundation
import XCTest

/// Implementation Gate REVIEW（第二轮）MUST 1：授权校验的每一个拒绝点必须能
/// 单独辨认，否则真实环境里的间歇失败无法定位。
///
/// FR-013／NFR-006：诊断只允许携带阶段标识、失败分类和 UTF-16 长度数字，
/// 任何被读到或将被写入的文字都不得进入诊断记录。
final class ReplacementStageDiagnosticsTests: XCTestCase {
    // MARK: - A1–A4：目标有效性的四个前置检查必须彼此可分

    func testTerminatedApplicationIsReportedAsItsOwnStage() async {
        let probe = await StageProbe.make()
        probe.host.terminateApplication()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .applicationRunning)
        XCTAssertEqual(stage?.failure, .invalidTarget)
    }

    func testFrontmostApplicationChangeIsReportedAsItsOwnStage() async {
        let probe = await StageProbe.make()
        probe.host.moveFocusToDifferentApplication()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .frontmostApplication)
        XCTAssertEqual(stage?.failure, .invalidTarget)
    }

    func testWindowIdentityChangeIsReportedAsItsOwnStage() async {
        let probe = await StageProbe.make()
        probe.host.switchWindow()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .windowIdentity)
        XCTAssertEqual(stage?.failure, .invalidTarget)
    }

    func testElementIdentityChangeIsReportedAsItsOwnStage() async {
        let probe = await StageProbe.make()
        probe.host.invalidateElement()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .elementIdentity)
        XCTAssertEqual(stage?.failure, .invalidTarget)
    }

    func testTheFourTargetValidityStagesAreAllDistinct() async {
        var stages: [ReplacementStage] = []
        for mutate in [
            { (host: SyntheticAXTextHost) in host.terminateApplication() },
            { (host: SyntheticAXTextHost) in host.moveFocusToDifferentApplication() },
            { (host: SyntheticAXTextHost) in host.switchWindow() },
            { (host: SyntheticAXTextHost) in host.invalidateElement() },
        ] {
            let probe = await StageProbe.make()
            mutate(probe.host)
            if let stage = await probe.attemptReplacement() {
                stages.append(stage.stage)
            }
        }

        XCTAssertEqual(stages.count, 4)
        XCTAssertEqual(
            Set(stages).count,
            4,
            "A1–A4 all return .invalidTarget, so only the stage can tell them apart"
        )
    }

    // MARK: - 能力、安全输入与可写性

    func testReadOnlyCapabilityIsReportedAsTheCapabilityStage() async {
        let probe = await StageProbe.make()
        probe.host.makeReadOnly()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .elementCapability)
        XCTAssertEqual(stage?.failure, .attributeNotSettable)
    }

    func testGlobalSecureInputIsReportedAsItsOwnStage() async {
        let probe = await StageProbe.make()
        probe.host.activateGlobalSecureInput()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .globalSecureInput)
        XCTAssertEqual(stage?.failure, .secureInputActive)
    }

    func testBlockedReplacementAttributeIsReportedAsTheSettableStage() async {
        let probe = await StageProbe.make()
        probe.host.blockReplacementAttribute()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(
            stage?.stage,
            .attributeSettable,
            "an editable element whose attribute is not settable is its own case"
        )
        XCTAssertEqual(stage?.failure, .attributeNotSettable)
    }

    // MARK: - B1 内容比较与内容读取失败必须区分

    func testExternalContentEditIsReportedAsTheComparisonStage() async {
        let probe = await StageProbe.make()
        let replacement = "SYNTHETIC-001 外部改过的文字"
        probe.host.editSegmentExternally(replacement)

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .contentComparison)
        XCTAssertEqual(stage?.failure, .sourceChanged)
        XCTAssertEqual(
            stage?.observedLength,
            replacement.utf16.count,
            "the report carries lengths so a mismatch is measurable"
        )
    }

    func testContentReadFailureIsDistinctFromContentComparison() async {
        let probe = await StageProbe.make()
        probe.host.failNextContentReads(1)

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .contentRead)
        XCTAssertNotEqual(
            stage?.stage,
            .contentComparison,
            "an unreadable target is not the same as a changed target"
        )
    }

    // MARK: - setter 与 readback 必须区分

    func testSetterFailureIsReportedAsTheSetterStage() async {
        let probe = await StageProbe.make()
        probe.host.failNextSetterAttempts(100)

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .setter)
        XCTAssertEqual(stage?.failure, .writeFailed)
    }

    func testReadbackFailureIsReportedAsTheReadbackStage() async {
        let probe = await StageProbe.make()
        probe.host.acceptSetterWithoutApplying()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(
            stage?.stage,
            .readback,
            "a silently dropped write must not look like a setter failure"
        )
        XCTAssertEqual(stage?.failure, .writeFailed)
    }

    // MARK: - A2 的聚焦应用归属

    /// 真人用鼠标点「确认替换」时面板会成为 key window，而 A2 读的是
    /// `kAXFocusedApplicationAttribute`，跟的是键盘焦点。若聚焦应用因此变成本
    /// 进程，A2 会把目标判为已变化。报告必须能区分"聚焦应用是本进程"与
    /// "聚焦应用是另一个外部应用"，否则无法判定这一点。
    func testFrontmostStageReportsWhenTheFocusedApplicationIsThisProcess() async {
        let probe = await StageProbe.make()
        probe.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .frontmostApplication)
        XCTAssertEqual(
            stage?.focusedApplicationIsSelf,
            true,
            "the panel taking keyboard focus must be distinguishable"
        )
    }

    func testFrontmostStageReportsWhenTheFocusedApplicationIsAnotherApp() async {
        let probe = await StageProbe.make()
        probe.host.moveFocusToDifferentApplication()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .frontmostApplication)
        XCTAssertEqual(
            stage?.focusedApplicationIsSelf,
            false,
            "a genuinely different application is not this process"
        )
    }

    func testStagesOtherThanFrontmostDoNotClaimFocusOwnership() async {
        let probe = await StageProbe.make()
        probe.host.switchWindow()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .windowIdentity)
        XCTAssertNil(
            stage?.focusedApplicationIsSelf,
            "only the A2 stage evaluates focus ownership"
        )
    }

    // MARK: - 成功路径与隐私边界

    func testSuccessfulReplacementReportsCompletionWithoutAFailure() async {
        let probe = await StageProbe.make()

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .completed)
        XCTAssertNil(stage?.failure)
    }

    func testNoReportEverCarriesContent() async {
        let marker = SyntheticAXTextHost.syntheticMarker
        var descriptions: [String] = []

        for mutate in [
            { (host: SyntheticAXTextHost) in host.switchWindow() },
            { (host: SyntheticAXTextHost) in
                host.editSegmentExternally("\(marker) 外部改过的文字")
            },
            { (host: SyntheticAXTextHost) in host.failNextSetterAttempts(100) },
            { (host: SyntheticAXTextHost) in host.acceptSetterWithoutApplying() },
            { (_: SyntheticAXTextHost) in },
        ] {
            let probe = await StageProbe.make()
            mutate(probe.host)
            _ = await probe.attemptReplacement()
            descriptions += probe.recorder.snapshot().map { String(describing: $0) }
        }

        XCTAssertFalse(descriptions.isEmpty)
        for description in descriptions {
            XCTAssertFalse(
                description.contains(marker),
                "FR-013: diagnostics must not carry captured or written text"
            )
            XCTAssertFalse(description.contains("文字"))
            XCTAssertFalse(description.contains("前缀"))
        }
    }
}

// MARK: - Probe

private struct StageProbe {
    let host: SyntheticAXTextHost
    let gateway: AccessibilityGateway
    let recorder: StageRecorderSpy
    let snapshot: AXWriteSnapshot

    static func make() async -> StageProbe {
        let host = SyntheticAXTextHost.selectionFixture()
        let recorder = StageRecorderSpy()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host,
            diagnostics: recorder
        )
        guard
            case .success(let captured) = await gateway.capture(
                sessionID: InteractionSessionID()
            ),
            let pid = await gateway.authoritativePID(for: captured.targetHandle)
        else {
            fatalError("the selection fixture must capture successfully")
        }
        let transformed = DeterministicTransformer().transform(captured.sourceText)
        return StageProbe(
            host: host,
            gateway: gateway,
            recorder: recorder,
            snapshot: AXWriteSnapshot(
                targetHandle: captured.targetHandle,
                pid: pid,
                captureMode: captured.captureMode,
                originalText: captured.sourceText,
                transformedText: transformed
            )
        )
    }

    /// Runs one authoritative replacement and returns the single stage report it
    /// produced.
    func attemptReplacement() async -> ReplacementStageReport? {
        _ = await gateway.replaceAfterAuthoritativeValidation(snapshot)
        return recorder.snapshot().last
    }
}

/// Recording must stay synchronous: the replacement sequence may not gain a
/// suspension point between the A1–A4 checks and the setter, or the TOCTOU
/// window the plan already discloses would widen.
private final class StageRecorderSpy: ReplacementDiagnosticsRecording, @unchecked Sendable {
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
