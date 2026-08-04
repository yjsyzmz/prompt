import AppKit
import XCTest

@MainActor
final class AXAuthoritativeWriteRecoveryTests: XCTestCase {
    private let handle = TargetHandle()
    private let pid: Int32 = 401
    private let range = AXTextRange(location: 4, length: 12)
    private let original = SourceText("SYNTHETIC-001-original")
    private let transformed = TransformedText(
        value: "【系统交互验证】\nSYNTHETIC-001-original"
    )

    func testSelectedReplacementRunsAllAuthoritativeChecksBeforeOneSetter() async {
        let fixture = makeFixture(mode: .selectedText(range))

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        let recovery = requireRecovery(result)
        XCTAssertEqual(recovery.targetHandle, handle)
        XCTAssertEqual(recovery.captureMode, .selectedText(range))
        XCTAssertEqual(recovery.originalText, original)
        XCTAssertEqual(recovery.expectedTransformedText, transformed)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 1)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 0)
        XCTAssertEqual(fixture.authority.currentSelectedText, transformed.value)
        XCTAssertEqual(
            fixture.authority.calls,
            [
                .targetApplicationRunning,
                .externalApplication,
                .windowIdentity,
                .elementIdentity,
                .elementCapability,
                .globalSecureInput,
                .selectedRange,
                .selectedText,
                .attributeSettable,
                .setSelectedText,
                // T-061: every readback is preceded by a validity check, so the
                // loop stops the moment the target can no longer report the
                // write instead of waiting out the whole budget. A2 is not
                // re-read here — the panel legitimately holds focus during a
                // mouse-driven confirmation.
                .targetApplicationRunning,
                .windowIdentity,
                .elementIdentity,
                .selectedRange,
                .selectedText,
            ]
        )
    }

    func testWholeFieldReplacementUsesOnlyWholeFieldSetter() async {
        let fixture = makeFixture(mode: .wholeField)

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        _ = requireRecovery(result)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 0)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.currentWholeValue, transformed.value)
    }

    func testStoppedTargetApplicationFailsClosedBeforeSetter() async {
        let fixture = makeFixture()
        fixture.authority.targetApplicationIsRunning = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.invalidTarget, result: result)
        XCTAssertEqual(fixture.authority.calls, [.targetApplicationRunning])
        assertZeroSetters(fixture)
    }

    func testExternalApplicationChangeFailsClosedBeforeSetter() async {
        let fixture = makeFixture()
        fixture.authority.currentExternalPID = 999

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.invalidTarget, result: result)
        XCTAssertEqual(
            fixture.authority.calls,
            [.targetApplicationRunning, .externalApplication]
        )
        assertZeroSetters(fixture)
    }

    func testWindowChangeFailsClosedBeforeSetter() async {
        let fixture = makeFixture()
        fixture.authority.windowIdentityMatches = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.invalidTarget, result: result)
        XCTAssertFalse(fixture.authority.calls.contains(.elementIdentity))
        assertZeroSetters(fixture)
    }

    func testElementChangeFailsClosedBeforeSetter() async {
        let fixture = makeFixture()
        fixture.authority.elementIdentityMatches = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.invalidTarget, result: result)
        XCTAssertTrue(fixture.authority.calls.contains(.elementIdentity))
        XCTAssertFalse(fixture.authority.calls.contains(.elementCapability))
        assertZeroSetters(fixture)
    }

    func testReadOnlySecureElementOrGlobalSecureInputEachBlocksSetter() async {
        let readOnly = makeFixture()
        readOnly.authority.elementCapability = .readOnly
        let readOnlyResult = await readOnly.gateway
            .replaceAfterAuthoritativeValidation(readOnly.snapshot)
        assertFailure(.attributeNotSettable, result: readOnlyResult)
        assertZeroSetters(readOnly)

        let secureElement = makeFixture()
        secureElement.authority.elementCapability = .secure
        let secureElementResult = await secureElement.gateway
            .replaceAfterAuthoritativeValidation(secureElement.snapshot)
        assertFailure(.secureInputActive, result: secureElementResult)
        assertZeroSetters(secureElement)

        let globalSecure = makeFixture()
        globalSecure.authority.globalSecureInputIsActive = true
        let globalSecureResult = await globalSecure.gateway
            .replaceAfterAuthoritativeValidation(globalSecure.snapshot)
        assertFailure(.secureInputActive, result: globalSecureResult)
        assertZeroSetters(globalSecure)
    }

    func testSelectedRangeChangeFailsClosedBeforeReadingSelectedTextOrSetter() async {
        let fixture = makeFixture(mode: .selectedText(range))
        fixture.authority.currentSelectedRange = AXTextRange(location: 8, length: 4)

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.sourceChanged, result: result)
        XCTAssertFalse(fixture.authority.calls.contains(.selectedText))
        assertZeroSetters(fixture)
    }

    func testSelectedTextChangeFailsClosedBeforeSetter() async {
        let fixture = makeFixture(mode: .selectedText(range))
        fixture.authority.currentSelectedText = "SYNTHETIC-001-changed"

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.sourceChanged, result: result)
        assertZeroSetters(fixture)
    }

    func testWholeFieldSourceChangeFailsClosedBeforeSetter() async {
        let fixture = makeFixture(mode: .wholeField)
        fixture.authority.currentWholeValue = "SYNTHETIC-001-changed"

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.sourceChanged, result: result)
        assertZeroSetters(fixture)
    }

    func testNonsettableAttributeFailsClosedBeforeSetter() async {
        let fixture = makeFixture()
        fixture.authority.replacementAttributeIsSettable = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.attributeNotSettable, result: result)
        XCTAssertTrue(fixture.authority.calls.contains(.attributeSettable))
        assertZeroSetters(fixture)
    }

    func testSetterFailureLeavesOriginalUnchangedAndOffersCopyResult() async {
        let fixture = makeFixture(mode: .selectedText(range))
        fixture.authority.setterSucceeds = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.writeFailed, result: result)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 1)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 0)
        XCTAssertEqual(fixture.authority.currentSelectedText, original.value)
        XCTAssertTrue(
            DomainFailureMapper()
                .presentation(for: .writeFailed)
                .safeNextActions
                .contains(.copyResult)
        )
    }

    func testSilentSelectedSetterFailureFailsClosedViaReadback() async {
        let fixture = makeFixture(mode: .selectedText(range))
        fixture.authority.setterAppliesValue = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.writeFailed, result: result)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 1)
        XCTAssertEqual(fixture.authority.currentSelectedText, original.value)
    }

    func testSilentWholeFieldSetterFailureFailsClosedViaReadback() async {
        let fixture = makeFixture(mode: .wholeField)
        fixture.authority.setterAppliesValue = false

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        assertFailure(.writeFailed, result: result)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 1)
        XCTAssertEqual(fixture.authority.currentWholeValue, original.value)
    }

    func testSilentSetterFailureDuringRecoveryFailsClosed() async {
        let fixture = makeFixture(mode: .selectedText(range))
        let replacement = await fixture.gateway
            .replaceAfterAuthoritativeValidation(fixture.snapshot)
        let recovery = requireRecovery(replacement)
        fixture.authority.setterAppliesValue = false

        let restoration = await fixture.gateway
            .restoreAfterAuthoritativeValidation(recovery)

        assertFailure(.recoveryTargetChanged, result: restoration)
        XCTAssertEqual(fixture.authority.currentSelectedText, transformed.value)
    }

    func testDelayedSetterApplicationIsConfirmedByReadbackRetry() async {
        let fixture = makeFixture(mode: .selectedText(range))
        fixture.authority.readbacksBeforeValueApplies = 2

        let result = await fixture.gateway.replaceAfterAuthoritativeValidation(
            fixture.snapshot
        )

        _ = requireRecovery(result)
        XCTAssertEqual(fixture.authority.currentSelectedText, transformed.value)
    }

    func testSuccessfulReplacementCanRestoreOriginalWithOneAdditionalSetter() async {
        let fixture = makeFixture(mode: .selectedText(range))
        let replacement = await fixture.gateway
            .replaceAfterAuthoritativeValidation(fixture.snapshot)
        let recovery = requireRecovery(replacement)
        fixture.authority.resetCalls()

        let restoration = await fixture.gateway
            .restoreAfterAuthoritativeValidation(recovery)

        assertSuccess(restoration)
        XCTAssertEqual(fixture.authority.selectedSetterCount, 2)
        XCTAssertEqual(fixture.authority.wholeFieldSetterCount, 0)
        XCTAssertEqual(fixture.authority.currentSelectedText, original.value)
        XCTAssertTrue(fixture.authority.calls.contains(.setSelectedText))
        XCTAssertNotEqual(fixture.authority.calls.last, .setSelectedText)
    }

    func testChangedResultBeforeRecoveryBlocksSetterAndOffersCopyOriginal() async {
        let fixture = makeFixture(mode: .selectedText(range))
        let replacement = await fixture.gateway
            .replaceAfterAuthoritativeValidation(fixture.snapshot)
        let recovery = requireRecovery(replacement)
        fixture.authority.currentSelectedText = "SYNTHETIC-001-after-replacement-change"
        let setterCountBeforeRecovery = fixture.authority.totalSetterCount

        let restoration = await fixture.gateway
            .restoreAfterAuthoritativeValidation(recovery)

        assertFailure(.recoveryTargetChanged, result: restoration)
        XCTAssertEqual(fixture.authority.totalSetterCount, setterCountBeforeRecovery)
        XCTAssertTrue(
            DomainFailureMapper()
                .presentation(for: .recoveryTargetChanged)
                .safeNextActions
                .contains(.copyOriginal)
        )
    }

    private func makeFixture(
        mode: CaptureMode = .selectedText(AXTextRange(location: 4, length: 12))
    ) -> AXWriteFixture {
        let authority = AXAuthoritativeTargetSpy(
            pid: pid,
            range: range,
            original: original.value
        )
        let gateway = AccessibilityGateway(
            captureReader: AXUnusedCaptureReader(),
            authoritativeTarget: authority
        )
        let snapshot = AXWriteSnapshot(
            targetHandle: handle,
            pid: pid,
            captureMode: mode,
            originalText: original,
            transformedText: transformed
        )
        return AXWriteFixture(
            gateway: gateway,
            authority: authority,
            snapshot: snapshot
        )
    }

    private func requireRecovery(
        _ result: Result<AXRecoveryContext, DomainFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AXRecoveryContext {
        guard case .success(let recovery) = result else {
            XCTFail("Expected replacement recovery context", file: file, line: line)
            preconditionFailure("Expected replacement recovery context")
        }
        return recovery
    }

    private func assertSuccess(
        _ result: Result<Void, DomainFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            XCTFail("Expected successful recovery", file: file, line: line)
            return
        }
    }

    private func assertFailure<Success>(
        _ expected: DomainFailure,
        result: Result<Success, DomainFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let failure) = result else {
            XCTFail("Expected fail-closed result", file: file, line: line)
            return
        }
        XCTAssertEqual(failure, expected, file: file, line: line)
    }

    private func assertZeroSetters(
        _ fixture: AXWriteFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(fixture.authority.totalSetterCount, 0, file: file, line: line)
    }
}

@MainActor
private struct AXWriteFixture {
    let gateway: AccessibilityGateway
    let authority: AXAuthoritativeTargetSpy
    let snapshot: AXWriteSnapshot
}

private enum AXAuthorityCall: Equatable {
    case targetApplicationRunning
    case externalApplication
    case windowIdentity
    case elementIdentity
    case elementCapability
    case globalSecureInput
    case selectedRange
    case selectedText
    case wholeValue
    case attributeSettable
    case setSelectedText
    case setWholeValue
}

private final class AXAuthoritativeTargetSpy: AXAuthoritativeTargetAccessing,
    @unchecked Sendable
{
    let expectedPID: Int32
    var targetApplicationIsRunning = true
    var currentExternalPID: Int32?
    var windowIdentityMatches = true
    var elementIdentityMatches = true
    var elementCapability: AXFocusedElementCapability = .editable
    var globalSecureInputIsActive = false
    var currentSelectedRange: AXTextRange
    var currentSelectedText: String
    var currentWholeValue: String
    var replacementAttributeIsSettable = true
    var setterSucceeds = true
    var setterAppliesValue = true
    var readbacksBeforeValueApplies = 0
    private var pendingSelectedText: String?

    private(set) var calls: [AXAuthorityCall] = []
    private(set) var selectedSetterCount = 0
    private(set) var wholeFieldSetterCount = 0

    var totalSetterCount: Int {
        selectedSetterCount + wholeFieldSetterCount
    }

    init(pid: Int32, range: AXTextRange, original: String) {
        expectedPID = pid
        currentExternalPID = pid
        currentSelectedRange = range
        currentSelectedText = original
        currentWholeValue = original
    }

    func resetCalls() {
        calls.removeAll()
    }

    func isTargetApplicationRunning(expectedPID: Int32) -> Bool {
        calls.append(.targetApplicationRunning)
        return targetApplicationIsRunning && expectedPID == self.expectedPID
    }

    func currentExternalApplicationPID() -> Int32? {
        calls.append(.externalApplication)
        return currentExternalPID
    }

    func windowIdentityMatches(targetHandle: TargetHandle) -> Bool {
        calls.append(.windowIdentity)
        return windowIdentityMatches
    }

    func elementIdentityMatches(targetHandle: TargetHandle) -> Bool {
        calls.append(.elementIdentity)
        return elementIdentityMatches
    }

    func currentElementCapability() -> AXFocusedElementCapability {
        calls.append(.elementCapability)
        return elementCapability
    }

    func isGlobalSecureInputActive() -> Bool {
        calls.append(.globalSecureInput)
        return globalSecureInputIsActive
    }

    func selectedTextRange() -> Result<AXTextRange, DomainFailure> {
        calls.append(.selectedRange)
        if let pending = pendingSelectedText {
            readbacksBeforeValueApplies -= 1
            if readbacksBeforeValueApplies <= 0 {
                currentSelectedText = pending
                currentSelectedRange = AXTextRange(
                    location: currentSelectedRange.location,
                    length: pending.utf16.count
                )
                pendingSelectedText = nil
            }
        }
        return .success(currentSelectedRange)
    }

    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure> {
        calls.append(.selectedText)
        return .success(currentSelectedText)
    }

    func fullValue() -> Result<String, DomainFailure> {
        calls.append(.wholeValue)
        return .success(currentWholeValue)
    }

    func isReplacementAttributeSettable(for mode: CaptureMode) -> Bool {
        calls.append(.attributeSettable)
        return replacementAttributeIsSettable
    }

    func setSelectedText(_ value: String) -> Bool {
        calls.append(.setSelectedText)
        selectedSetterCount += 1
        guard setterSucceeds else {
            return false
        }
        guard setterAppliesValue else {
            return true
        }
        if readbacksBeforeValueApplies > 0 {
            pendingSelectedText = value
            return true
        }
        currentSelectedText = value
        currentSelectedRange = AXTextRange(
            location: currentSelectedRange.location,
            length: value.utf16.count
        )
        return true
    }

    func setWholeValue(_ value: String) -> Bool {
        calls.append(.setWholeValue)
        wholeFieldSetterCount += 1
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

private struct AXUnusedCaptureReader: AXCaptureReading {
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
