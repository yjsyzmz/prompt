import AppKit
import XCTest

/// T-021（重写）：按 Plan Gate 第三版修订 `0c9883f` 批准的算法建立失败优先测试。
///
/// 覆盖 tasks.md 的第 2、4、5、6、7、8、9、10 组要求：路径化 settable 检查、
/// recovery 入口分支、whole-field recovery W1–W4、selected recovery C1–C4 与
/// R1／R2／R3 分类、R2 不推断来源语义、fallback 六项门禁逐项失败与 setter
/// 计数、UTF-16 夹具、失败后保留原文。
///
/// 第 1 组（共享前置检查 A1–A4）与第 3 组（replacement B1–B2）的逐项失败
/// 断言位于 `AXAuthoritativeWriteRecoveryTests`；本文件补充"A1–A4 任一失败时
/// fallback 也不得执行"的交叉断言。
@MainActor
final class AXRecoveryAlgorithmTests: XCTestCase {
    private let handle = TargetHandle()
    private let pid: Int32 = 407
    private let original = SourceText("SYNTHETIC-001-original")
    private let marker = "【系统交互验证】\n"

    private var transformedValue: String {
        marker + original.value
    }

    private var transformed: TransformedText {
        TransformedText(value: transformedValue)
    }

    /// 捕获时记录的选区起点；结果范围 = location + transformed 的 UTF-16 长度。
    private let capturedLocation = 6

    private var capturedRange: AXTextRange {
        AXTextRange(location: capturedLocation, length: original.value.utf16.count)
    }

    private var expectedResultRange: AXTextRange {
        AXTextRange(location: capturedLocation, length: transformedValue.utf16.count)
    }

    private let prefix = "SYNTHETIC-001 前缀："
    private let suffix = "：SYNTHETIC-001 后缀"

    // MARK: - 第 4 组：recovery 入口分支

    func testClipboardInputRecoveryIsRejectedWithoutAnySetter() async {
        let fixture = makeFixture(mode: .clipboardInput, fieldContainsTransformed: true)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    // MARK: - 第 5 组：whole-field recovery W1–W4

    func testWholeFieldRecoverySucceedsWithExactlyOneValueSetter() async {
        let fixture = makeFixture(mode: .wholeField, fieldContainsTransformed: true)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
        XCTAssertEqual(fixture.authority.currentWholeValue, original.value)
    }

    /// W1–W4 不得依赖任何 selected-range 能力。
    func testWholeFieldRecoveryNeverReadsSelectedRange() async {
        let fixture = makeFixture(mode: .wholeField, fieldContainsTransformed: true)
        fixture.authority.selectedRangeOutcome = .failure(.invalidTarget)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(
            fixture.authority.selectedRangeReadCount,
            0,
            "whole-field recovery must not read the selected range"
        )
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
    }

    func testWholeFieldRecoveryRejectsChangedValueWithoutSetter() async {
        let fixture = makeFixture(mode: .wholeField, fieldContainsTransformed: true)
        fixture.authority.currentWholeValue = "SYNTHETIC-001-changed-by-user"

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    func testWholeFieldRecoveryRejectsUnsettableValueAttribute() async {
        let fixture = makeFixture(mode: .wholeField, fieldContainsTransformed: true)
        fixture.authority.settableModes = [:]

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
        XCTAssertEqual(
            fixture.authority.settableQueriedModes,
            [.wholeField],
            "whole-field recovery must check kAXValueAttribute only"
        )
    }

    func testWholeFieldRecoveryRejectsMismatchedReadback() async {
        let fixture = makeFixture(mode: .wholeField, fieldContainsTransformed: true)
        fixture.authority.setterAppliesValue = false

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
    }

    // MARK: - 第 6 组：selected recovery R1

    func testSelectedRecoveryR1UsesSelectedSetterOnly() async {
        let fixture = makeSelectedFixture(currentRange: expectedResultRange)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 1)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 0)
        XCTAssertEqual(
            fixture.authority.settableQueriedModes,
            [.selectedText(capturedRange)],
            "R1 must check kAXSelectedTextAttribute"
        )
    }

    // MARK: - 第 6／7 组：R2 两种情形

    func testSelectedRecoveryR2CollapsedCaretEntersConstrainedFallback() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
        XCTAssertEqual(fixture.authority.currentWholeValue, prefix + original.value + suffix)
    }

    func testSelectedRecoveryR2AcceptsCaretAtEitherBoundary() async {
        for location in [capturedLocation, capturedLocation + transformedValue.utf16.count] {
            let fixture = makeSelectedFixture(
                currentRange: AXTextRange(location: location, length: 0)
            )

            let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
                fixture.recovery
            )

            assertSuccess(result)
            XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        }
    }

    func testSelectedRecoveryR2MissingRangeCapabilityEntersFallback() async {
        let fixture = makeSelectedFixture(currentRange: expectedResultRange)
        fixture.authority.selectedRangeOutcome = .failure(.unsupportedTarget)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
    }

    /// R2 授权可观察状态，不推断产生原因：范围内的零长度插入点无论来自应用
    /// 塌陷还是用户移动光标，都进入受约束 fallback。
    func testSelectedRecoveryR2DoesNotInferCaretProvenance() async {
        let insideCaret = AXTextRange(
            location: capturedLocation + 3,
            length: 0
        )
        let fixture = makeSelectedFixture(currentRange: insideCaret)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
    }

    /// 同一可观察状态下，若范围内文本已被改动，必须由门禁 4 拦截。
    func testSelectedRecoveryR2WithEditedRangeIsBlockedByPrecondition4() async {
        let insideCaret = AXTextRange(location: capturedLocation + 2, length: 0)
        let fixture = makeSelectedFixture(currentRange: insideCaret)
        fixture.authority.currentWholeValue = prefix + "SYNTHETIC-001-edited" + suffix

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    // MARK: - 第 6 组：R3 必须立即 fail-closed

    func testSelectedRecoveryR3ErrorsFailClosedWithoutFallback() async {
        let r3Failures: [DomainFailure] = [
            .invalidTarget,
            .axTimedOut,
            .axCannotComplete,
            .accessibilityPermissionRequired,
            .secureInputActive,
        ]

        for failure in r3Failures {
            let fixture = makeSelectedFixture(currentRange: expectedResultRange)
            fixture.authority.selectedRangeOutcome = .failure(failure)

            let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
                fixture.recovery
            )

            guard case .failure(let observed) = result else {
                XCTFail("R3 must fail closed for \(failure)")
                continue
            }
            XCTAssertNotEqual(
                observed,
                .recoveryTargetChanged,
                "R3 must surface the safety error, not a generic range mismatch: \(failure)"
            )
            XCTAssertEqual(
                fixture.authority.totalSetterCount,
                0,
                "R3 must never write for \(failure)"
            )
        }
    }

    // MARK: - 第 6 组：C2 两类排除项

    func testSelectedRecoveryRejectsNonZeroLengthRangeMismatch() async {
        let userSelection = AXTextRange(location: capturedLocation, length: 3)
        let fixture = makeSelectedFixture(currentRange: userSelection)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    func testSelectedRecoveryRejectsCaretOutsideResultRange() async {
        let outsideCaret = AXTextRange(location: 0, length: 0)
        let fixture = makeSelectedFixture(currentRange: outsideCaret)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    // MARK: - 第 2 组：路径化 settable 检查

    func testUnsettableSelectedAttributeDoesNotBlockR2Fallback() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.settableModes = [.wholeFieldKey: true]

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(
            result,
            message: "an unsettable kAXSelectedTextAttribute must not block the fallback"
        )
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
    }

    // MARK: - 第 8 组：fallback 六项门禁

    func testFallbackPrecondition1RejectsUnsettableValueAttribute() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.settableModes = [:]

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    func testFallbackPrecondition2RejectsUnreadableFullValue() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.fullValueOutcome = .failure(.axCannotComplete)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    /// 基值必须在全部门禁通过后紧邻 setter 获取并校验，不得复用旧值。
    func testFallbackPrecondition2UsesFreshlyValidatedBaseValue() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        let staleSuffix = "：SYNTHETIC-001 旧后缀"
        fixture.authority.currentWholeValue = prefix + transformedValue + staleSuffix
        fixture.authority.mutateWholeValueBeforeSetter = { [prefix, suffix, transformedValue] in
            prefix + transformedValue + suffix
        }

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        XCTAssertEqual(
            fixture.authority.lastWrittenWholeValue,
            prefix + original.value + suffix,
            "the written value must be derived from the freshly read base value"
        )
        XCTAssertFalse(
            fixture.authority.lastWrittenWholeValue?.contains("旧后缀") ?? false,
            "a stale base value must not be written back"
        )
    }

    func testFallbackPrecondition3RejectsOutOfBoundsResultRange() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.currentWholeValue = prefix + marker

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    func testFallbackPrecondition3RejectsNegativeLocation() async {
        let caret = AXTextRange(location: -1, length: 0)
        let fixture = makeSelectedFixture(
            currentRange: caret,
            capturedRangeOverride: AXTextRange(location: -1, length: original.value.utf16.count)
        )

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    func testFallbackPrecondition4RejectsRangeContentMismatch() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        let sameLengthDifferentText = String(
            repeating: "X",
            count: transformedValue.utf16.count
        )
        fixture.authority.currentWholeValue = prefix + sameLengthDifferentText + suffix

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    func testFallbackPrecondition5KeepsEveryCodeUnitOutsideTheRange() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertSuccess(result)
        let written = fixture.authority.currentWholeValue as NSString
        XCTAssertEqual(
            written.substring(to: capturedLocation),
            prefix,
            "code units before the range must be unchanged"
        )
        XCTAssertEqual(
            written.substring(from: capturedLocation + original.value.utf16.count),
            suffix,
            "code units after the range must be unchanged"
        )
    }

    func testFallbackPrecondition6RejectsMismatchedReadback() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.setterAppliesValue = false

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
    }

    func testFallbackSetterFailureDoesNotRetryAnotherSetter() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.setterSucceeds = false

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        assertFailure(.recoveryTargetChanged, result: result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(
            fixture.authority.selectedSetterCount,
            0,
            "a failed whole-field setter must not fall back to the selected setter"
        )
    }

    func testSharedPrecheckFailureAlsoBlocksFallback() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)
        let fixture = makeSelectedFixture(currentRange: caret)
        fixture.authority.globalSecureInputIsActive = true

        let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
            fixture.recovery
        )

        guard case .failure = result else {
            XCTFail("A1–A4 failure must block the fallback")
            return
        }
        XCTAssertEqual(fixture.authority.totalSetterCount, 0)
    }

    // MARK: - 第 9 组：UTF-16 单位夹具

    func testFallbackHandlesEmojiCombiningMarksAndSurrogatePairs() async {
        // 😀 与 𝄞 为代理对，e + U+0301 为组合字符序列。
        let tricky = "SYNTHETIC-001 😀 e\u{0301} 𝄞 组合"
        let trickyOriginal = SourceText(tricky)
        let trickyTransformed = TransformedText(value: marker + tricky)
        let trickyPrefix = "😀SYNTHETIC-001 前缀"
        let trickySuffix = "e\u{0301}𝄞后缀"
        let location = (trickyPrefix as NSString).length
        let captured = AXTextRange(location: location, length: (tricky as NSString).length)

        let authority = AXRecoveryTargetSpy(pid: pid)
        authority.currentWholeValue = trickyPrefix + trickyTransformed.value + trickySuffix
        authority.selectedRangeOutcome = .success(AXTextRange(location: location, length: 0))
        let gateway = AccessibilityGateway(
            captureReader: AXRecoveryUnusedCaptureReader(),
            authoritativeTarget: authority
        )
        let recovery = AXRecoveryContext(
            targetHandle: handle,
            pid: pid,
            captureMode: .selectedText(captured),
            originalText: trickyOriginal,
            expectedTransformedText: trickyTransformed
        )

        let result = await gateway.restoreAfterAuthoritativeValidation(recovery)

        assertSuccess(result)
        XCTAssertEqual(
            authority.currentWholeValue,
            trickyPrefix + tricky + trickySuffix,
            "UTF-16 range math must restore the original without touching neighbours"
        )
    }

    // MARK: - 第 10 组：失败后保留原文

    func testEveryRecoveryFailureLeavesTargetContentUntouched() async {
        let caret = AXTextRange(location: capturedLocation, length: 0)

        let cases: [(String, (AXRecoveryTargetSpy) -> Void)] = [
            ("unsettable", { $0.settableModes = [:] }),
            ("unreadable", { $0.fullValueOutcome = .failure(.axCannotComplete) }),
            ("secureInput", { $0.globalSecureInputIsActive = true }),
            ("r3", { $0.selectedRangeOutcome = .failure(.invalidTarget) }),
        ]

        for (name, configure) in cases {
            let fixture = makeSelectedFixture(currentRange: caret)
            let before = fixture.authority.currentWholeValue
            configure(fixture.authority)

            let result = await fixture.gateway.restoreAfterAuthoritativeValidation(
                fixture.recovery
            )

            guard case .failure = result else {
                XCTFail("expected fail-closed recovery for \(name)")
                continue
            }
            XCTAssertEqual(
                fixture.authority.currentWholeValue,
                before,
                "target content must be untouched after \(name) failure"
            )
        }
    }

    // MARK: - Fixtures

    private func makeFixture(
        mode: CaptureMode,
        fieldContainsTransformed: Bool
    ) -> AXRecoveryFixture {
        let authority = AXRecoveryTargetSpy(pid: pid)
        authority.currentWholeValue = fieldContainsTransformed
            ? transformedValue
            : original.value
        let gateway = AccessibilityGateway(
            captureReader: AXRecoveryUnusedCaptureReader(),
            authoritativeTarget: authority
        )
        let recovery = AXRecoveryContext(
            targetHandle: handle,
            pid: pid,
            captureMode: mode,
            originalText: original,
            expectedTransformedText: transformed
        )
        return AXRecoveryFixture(
            gateway: gateway,
            authority: authority,
            recovery: recovery
        )
    }

    private func makeSelectedFixture(
        currentRange: AXTextRange,
        capturedRangeOverride: AXTextRange? = nil
    ) -> AXRecoveryFixture {
        let authority = AXRecoveryTargetSpy(pid: pid)
        authority.currentWholeValue = prefix + transformedValue + suffix
        authority.selectedRangeOutcome = .success(currentRange)
        authority.currentSelectedText = transformedValue
        let gateway = AccessibilityGateway(
            captureReader: AXRecoveryUnusedCaptureReader(),
            authoritativeTarget: authority
        )
        let recovery = AXRecoveryContext(
            targetHandle: handle,
            pid: pid,
            captureMode: .selectedText(capturedRangeOverride ?? capturedRange),
            originalText: original,
            expectedTransformedText: transformed
        )
        return AXRecoveryFixture(
            gateway: gateway,
            authority: authority,
            recovery: recovery
        )
    }

    private func assertSuccess(
        _ result: Result<Void, DomainFailure>,
        message: String = "Expected successful recovery",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            XCTFail(message, file: file, line: line)
            return
        }
    }

    private func assertFailure(
        _ expected: DomainFailure,
        result: Result<Void, DomainFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let failure) = result else {
            XCTFail("Expected fail-closed result", file: file, line: line)
            return
        }
        XCTAssertEqual(failure, expected, file: file, line: line)
    }
}

// MARK: - Fixture types

@MainActor
private struct AXRecoveryFixture {
    let gateway: AccessibilityGateway
    let authority: AXRecoveryTargetSpy
    let recovery: AXRecoveryContext
}

/// `settableModes` 的键：区分被查询的属性而不依赖 range 值。
private enum SettableModeKey: Hashable {
    case selected
    case wholeField
}

extension SettableModeKey {
    static let wholeFieldKey = SettableModeKey.wholeField
}

private final class AXRecoveryTargetSpy: AXAuthoritativeTargetAccessing,
    @unchecked Sendable
{
    let expectedPID: Int32
    var targetApplicationIsRunning = true
    var currentExternalPID: Int32?
    var windowIdentityMatches = true
    var elementIdentityMatches = true
    var elementCapability: AXFocusedElementCapability = .editable
    var globalSecureInputIsActive = false

    var selectedRangeOutcome: Result<AXTextRange, DomainFailure> = .success(
        AXTextRange(location: 0, length: 0)
    )
    var currentSelectedText = ""
    var currentWholeValue = ""
    var fullValueOutcome: Result<String, DomainFailure>?
    /// 门禁通过后、setter 之前改写目标全文，用于验证基值是紧邻读取的。
    var mutateWholeValueBeforeSetter: (() -> String)?
    var settableModes: [SettableModeKey: Bool] = [.selected: true, .wholeField: true]
    var setterSucceeds = true
    var setterAppliesValue = true

    private(set) var selectedRangeReadCount = 0
    private(set) var selectedSetterCount = 0
    private(set) var wholeFieldSetterCount = 0
    private(set) var settableQueriedModes: [CaptureMode] = []
    private(set) var lastWrittenWholeValue: String?
    private var fullValueReadCount = 0

    var totalSetterCount: Int {
        selectedSetterCount + wholeFieldSetterCount
    }

    init(pid: Int32) {
        expectedPID = pid
        currentExternalPID = pid
    }

    func isTargetApplicationRunning(expectedPID: Int32) -> Bool {
        targetApplicationIsRunning && expectedPID == self.expectedPID
    }

    func currentExternalApplicationPID() -> Int32? {
        currentExternalPID
    }

    func windowIdentityMatches(targetHandle: TargetHandle) -> Bool {
        windowIdentityMatches
    }

    func elementIdentityMatches(targetHandle: TargetHandle) -> Bool {
        elementIdentityMatches
    }

    func currentElementCapability() -> AXFocusedElementCapability {
        elementCapability
    }

    func isGlobalSecureInputActive() -> Bool {
        globalSecureInputIsActive
    }

    func selectedTextRange() -> Result<AXTextRange, DomainFailure> {
        selectedRangeReadCount += 1
        return selectedRangeOutcome
    }

    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure> {
        .success(currentSelectedText)
    }

    func fullValue() -> Result<String, DomainFailure> {
        if let outcome = fullValueOutcome {
            return outcome
        }
        fullValueReadCount += 1
        if fullValueReadCount == 1, let mutate = mutateWholeValueBeforeSetter {
            currentWholeValue = mutate()
        }
        return .success(currentWholeValue)
    }

    func isReplacementAttributeSettable(for mode: CaptureMode) -> Bool {
        settableQueriedModes.append(mode)
        switch mode {
        case .selectedText:
            return settableModes[.selected] ?? false
        case .wholeField:
            return settableModes[.wholeField] ?? false
        case .clipboardInput:
            return false
        }
    }

    func setSelectedText(_ value: String) -> Bool {
        selectedSetterCount += 1
        guard setterSucceeds else {
            return false
        }
        guard setterAppliesValue else {
            return true
        }
        // Keep the full value consistent with the selection write so that
        // readback confirmation behaves like a real text field.
        if case .success(let range) = selectedRangeOutcome {
            let full = currentWholeValue as NSString
            let target = NSRange(location: range.location, length: range.length)
            if target.location >= 0, NSMaxRange(target) <= full.length {
                currentWholeValue = full.replacingCharacters(in: target, with: value)
            }
            selectedRangeOutcome = .success(
                AXTextRange(location: range.location, length: (value as NSString).length)
            )
        }
        currentSelectedText = value
        return true
    }

    func setWholeValue(_ value: String) -> Bool {
        wholeFieldSetterCount += 1
        lastWrittenWholeValue = value
        guard setterSucceeds else {
            return false
        }
        guard setterAppliesValue else {
            return true
        }
        currentWholeValue = value
        return true
    }
}

private struct AXRecoveryUnusedCaptureReader: AXCaptureReading {
    func focusedElementCapability() -> Result<AXFocusedElementCapability, DomainFailure> {
        .failure(.unsupportedTarget)
    }

    func selectedTextRange() -> Result<AXTextRange, DomainFailure> {
        .failure(.unsupportedTarget)
    }

    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure> {
        .failure(.unsupportedTarget)
    }

    func fullValue() -> Result<String, DomainFailure> {
        .failure(.unsupportedTarget)
    }

    func bounds(for range: AXTextRange) -> Result<CGRect?, DomainFailure> {
        .failure(.unsupportedTarget)
    }
}
