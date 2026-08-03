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
        probe.host.editSegmentExternally("SYNTHETIC-001 外部改过的文字")

        let stage = await probe.attemptReplacement()

        XCTAssertEqual(stage?.stage, .contentComparison)
        XCTAssertEqual(stage?.failure, .sourceChanged)
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

    /// Plan `0c9883f` 第 197 行的 A2 原文是「**除工具自身 non-activating panel
    /// 外**，没有其他应用成为用户的新外部目标」。真人用鼠标点「确认替换」时面板
    /// 会成为 key window，`kAXFocusedApplicationAttribute` 随之指向本进程——这正
    /// 是该豁免要覆盖的情形，不得据此拒绝写入。
    func testFocusOnThisProcessWithPanelKeyDoesNotBlockTheReplacement() async {
        let probe = await StageProbe.make()
        probe.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let stage = await probe.attemptReplacement(
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        XCTAssertEqual(
            stage?.stage,
            .completed,
            "the approved A2 exempts this tool's own panel from the check"
        )
        XCTAssertNil(stage?.failure)
    }

    /// T-053：豁免的范围是**当前会话的预览面板**，不是本进程。焦点落在本进程的
    /// 其他窗口（设置窗口、关于窗口、或面板已关闭而焦点仍在本进程）时必须拒绝。
    func testFocusOnThisProcessWithoutPanelKeyIsRejected() async {
        let probe = await StageProbe.make()
        probe.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let stage = await probe.attemptReplacement(
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: false)
        )

        XCTAssertEqual(
            stage?.stage,
            .frontmostApplication,
            "process-wide focus is not an exemption; only the session panel is"
        )
        XCTAssertEqual(stage?.failure, .invalidTarget)
        XCTAssertEqual(
            stage?.focusedApplicationIsSelf,
            true,
            "the report must still say the focus was on this process"
        )
        XCTAssertEqual(
            probe.host.setterAttemptCount,
            0,
            "a rejected A2 must not reach the setter"
        )
    }

    /// 面板持有焦点的授权不得帮助另一个外部应用通过 A2。
    func testPanelKeyDoesNotExemptADifferentExternalApplication() async {
        let probe = await StageProbe.make()
        probe.host.moveFocusToDifferentApplication()

        let stage = await probe.attemptReplacement(
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        XCTAssertEqual(stage?.stage, .frontmostApplication)
        XCTAssertEqual(stage?.failure, .invalidTarget)
        XCTAssertEqual(
            stage?.focusedApplicationIsSelf,
            false,
            "a genuinely different application is not this process"
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

    /// A1–A4 在实现里有两份拷贝：替换路径在 `validate`，恢复路径在
    /// `sharedPrechecks`。只给前者补上 Plan `0c9883f` 第 197 行的自身豁免，会让
    /// 「替换成功但恢复原文失败」——真人点「恢复原文」时面板同样持有键盘焦点。
    func testFocusOnThisProcessDoesNotBlockTheRecovery() async {
        let probe = await StageProbe.make()
        let originalFullText = probe.host.fullText
        guard case .success(let context) = await probe.gateway
            .replaceAfterAuthoritativeValidation(
                probe.snapshot,
                panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
            )
        else {
            XCTFail("the replacement must succeed before recovery is meaningful")
            return
        }
        XCTAssertNotEqual(
            probe.host.fullText,
            originalFullText,
            "the replacement must have changed the field"
        )
        probe.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let result = await probe.gateway.restoreAfterAuthoritativeValidation(
            context,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
        )

        guard case .success = result else {
            XCTFail(
                "recovery must apply the same A2 exemption as the replacement path"
            )
            return
        }
        XCTAssertEqual(
            probe.host.fullText,
            originalFullText,
            "the field must be back to its pre-replacement content"
        )
    }

    /// T-053：恢复路径的豁免范围同样限定为当前会话面板。
    func testRecoveryIsRejectedWhenFocusIsThisProcessButNotThePanel() async {
        let probe = await StageProbe.make()
        guard case .success(let context) = await probe.gateway
            .replaceAfterAuthoritativeValidation(
                probe.snapshot,
                panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: true)
            )
        else {
            XCTFail("the replacement must succeed before recovery is meaningful")
            return
        }
        let textAfterReplacement = probe.host.fullText
        probe.host.setFrontmostApplication(
            pid: ProcessInfo.processInfo.processIdentifier
        )

        let result = await probe.gateway.restoreAfterAuthoritativeValidation(
            context,
            panelFocus: PanelFocusAuthorization(currentSessionPanelIsKey: false)
        )

        guard case .failure(let failure) = result else {
            XCTFail("recovery must be refused without the session panel key")
            return
        }
        XCTAssertEqual(failure, .invalidTarget)
        XCTAssertEqual(
            probe.host.fullText,
            textAfterReplacement,
            "a refused recovery must not write anything"
        )
    }

    // MARK: - T-052：诊断不得携带任何内容度量

    /// Tasks Gate 裁决：完全删除长度字段，不允许等级化表示。长度是用户文字的
    /// 可观测元数据，FR-013／NFR-006 的边界不接受以「风险披露」豁免。
    func testStageReportHasNoNumericContentMeasureField() async {
        let probe = await StageProbe.make()
        probe.host.switchWindow()
        _ = await probe.attemptReplacement()

        let reports = probe.recorder.snapshot()
        XCTAssertFalse(reports.isEmpty)
        for report in reports {
            for child in Mirror(reflecting: report).children {
                let typeName = String(describing: type(of: child.value))
                XCTAssertFalse(
                    typeName.contains("Int"),
                    """
                    FR-013: a stage report may not carry a numeric measure of \
                    user text; found \(child.label ?? "?") of type \(typeName)
                    """
                )
            }
        }
    }

    func testStageReportDescriptionContainsNoDigits() async {
        let probe = await StageProbe.make()
        probe.host.editSegmentExternally("SYNTHETIC-001 外部改过的文字")
        _ = await probe.attemptReplacement()

        let descriptions = probe.recorder.snapshot().map { String(describing: $0) }
        XCTAssertFalse(descriptions.isEmpty)
        for description in descriptions {
            XCTAssertNil(
                description.rangeOfCharacter(from: .decimalDigits),
                "FR-013: diagnostics must not expose any digit derived from content"
            )
        }
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
    /// Runs one authoritative replacement and returns the single stage report it
    /// produced. `panelFocus` defaults to the session panel holding focus,
    /// because that is what a real mouse-driven confirmation looks like.
    func attemptReplacement(
        panelFocus: PanelFocusAuthorization = PanelFocusAuthorization(
            currentSessionPanelIsKey: true
        )
    ) async -> ReplacementStageReport? {
        _ = await gateway.replaceAfterAuthoritativeValidation(
            snapshot,
            panelFocus: panelFocus
        )
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
