import AppKit
import XCTest

@MainActor
final class AXTargetCaptureTests: XCTestCase {
    private let sessionID = InteractionSessionID()
    private let selectedRange = AXTextRange(location: 7, length: 13)

    func testSecureElementIsRejectedBeforeContentReadOrSourceValueCreation() async {
        let fixture = makeFixture(capability: .secure)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        assertFailure(.secureInputActive, result: result)
        XCTAssertEqual(fixture.reader.selectedRangeReadCount, 0)
        XCTAssertEqual(fixture.reader.selectedTextReadCount, 0)
        XCTAssertEqual(fixture.reader.fullValueReadCount, 0)
        XCTAssertEqual(fixture.reader.boundsReadCount, 0)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 0)
    }

    func testNonemptySelectionIsPreferredWithoutReadingFullValue() async {
        let fixture = makeFixture()
        fixture.reader.selectedRangeResult = .success(selectedRange)
        fixture.reader.selectedTextResult = .success("SYNTHETIC-001-selection")
        fixture.reader.boundsResult = .success(
            CGRect(x: 120, y: 240, width: 80, height: 22)
        )

        let result = await fixture.gateway.capture(sessionID: sessionID)

        let capture = requireCapture(result)
        XCTAssertEqual(capture.sessionID, sessionID)
        XCTAssertEqual(capture.sourceText.value, "SYNTHETIC-001-selection")
        XCTAssertEqual(capture.captureMode, .selectedText(selectedRange))
        XCTAssertEqual(
            capture.anchorRect,
            CGRect(x: 120, y: 240, width: 80, height: 22)
        )
        XCTAssertEqual(fixture.reader.selectedTextReadCount, 1)
        XCTAssertEqual(fixture.reader.fullValueReadCount, 0)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 1)
    }

    func testZeroLengthSelectionFallsBackToWholeField() async {
        let fixture = makeFixture()
        fixture.reader.selectedRangeResult = .success(
            AXTextRange(location: 5, length: 0)
        )
        fixture.reader.fullValueResult = .success("SYNTHETIC-001-whole-field")

        let result = await fixture.gateway.capture(sessionID: sessionID)

        let capture = requireCapture(result)
        XCTAssertEqual(capture.sourceText.value, "SYNTHETIC-001-whole-field")
        XCTAssertEqual(capture.captureMode, .wholeField)
        XCTAssertEqual(fixture.reader.selectedTextReadCount, 0)
        XCTAssertEqual(fixture.reader.fullValueReadCount, 1)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 1)
    }

    func testEmptyTextIsRejectedWithoutCreatingSourceValue() async {
        let fixture = makeFixture()
        fixture.reader.fullValueResult = .success("")

        let result = await fixture.gateway.capture(sessionID: sessionID)

        assertFailure(.emptySource, result: result)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 0)
    }

    func testUnsupportedElementIsRejectedBeforeContentRead() async {
        let fixture = makeFixture(capability: .unsupported)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        assertFailure(.unsupportedTarget, result: result)
        assertZeroContentAccess(fixture)
    }

    func testReadOnlyElementIsRejectedBeforeContentRead() async {
        let fixture = makeFixture(capability: .readOnly)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        assertFailure(.unsupportedTarget, result: result)
        assertZeroContentAccess(fixture)
    }

    func testWhitespaceOnlyTextIsValidAndPreservedExactly() async {
        let fixture = makeFixture()
        let whitespace = " \n\t  "
        fixture.reader.fullValueResult = .success(whitespace)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        let capture = requireCapture(result)
        XCTAssertEqual(capture.sourceText.value, whitespace)
        XCTAssertEqual(capture.captureMode, .wholeField)
        XCTAssertEqual(fixture.sourceTextFactory.createdValues, [whitespace])
    }

    func testAvailableBoundsAreReturnedAsOptionalAnchor() async {
        let fixture = makeFixture()
        let bounds = CGRect(x: -320, y: 480, width: 140, height: 24)
        fixture.reader.fullValueResult = .success("SYNTHETIC-001-bounds")
        fixture.reader.boundsResult = .success(bounds)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        XCTAssertEqual(requireCapture(result).anchorRect, bounds)
        XCTAssertEqual(fixture.reader.boundsReadCount, 1)
    }

    func testUnavailableBoundsDoNotTurnSuccessfulCaptureIntoFailure() async {
        let fixture = makeFixture()
        fixture.reader.fullValueResult = .success("SYNTHETIC-001-no-bounds")
        fixture.reader.boundsResult = .success(nil)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        let capture = requireCapture(result)
        XCTAssertEqual(capture.sourceText.value, "SYNTHETIC-001-no-bounds")
        XCTAssertNil(capture.anchorRect)
        XCTAssertEqual(fixture.reader.boundsReadCount, 1)
    }

    func testSelectedTextReadErrorFailsClosedWithoutCreatingSourceValue() async {
        let fixture = makeFixture()
        fixture.reader.selectedRangeResult = .success(selectedRange)
        fixture.reader.selectedTextResult = .failure(.axCannotComplete)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        assertFailure(.axCannotComplete, result: result)
        XCTAssertEqual(fixture.reader.fullValueReadCount, 0)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 0)
    }

    func testWholeValueReadErrorFailsClosedWithoutCreatingSourceValue() async {
        let fixture = makeFixture()
        fixture.reader.fullValueResult = .failure(.axCannotComplete)

        let result = await fixture.gateway.capture(sessionID: sessionID)

        assertFailure(.axCannotComplete, result: result)
        XCTAssertEqual(fixture.reader.selectedTextReadCount, 0)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 0)
    }

    private func makeFixture(
        capability: AXFocusedElementCapability = .editable
    ) -> AXCaptureFixture {
        let reader = AXCaptureReaderSpy(capability: capability)
        let sourceTextFactory = SourceTextFactorySpy()
        let gateway = AccessibilityGateway(
            captureReader: reader,
            sourceTextFactory: sourceTextFactory
        )
        return AXCaptureFixture(
            gateway: gateway,
            reader: reader,
            sourceTextFactory: sourceTextFactory
        )
    }

    private func requireCapture(
        _ result: Result<AXCapturedTarget, DomainFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AXCapturedTarget {
        guard case .success(let capture) = result else {
            XCTFail("Expected successful AX capture", file: file, line: line)
            preconditionFailure("Expected successful AX capture")
        }
        return capture
    }

    private func assertFailure(
        _ expected: DomainFailure,
        result: Result<AXCapturedTarget, DomainFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let failure) = result else {
            XCTFail("Expected AX capture failure", file: file, line: line)
            return
        }
        XCTAssertEqual(failure, expected, file: file, line: line)
    }

    private func assertZeroContentAccess(
        _ fixture: AXCaptureFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(fixture.reader.selectedRangeReadCount, 0, file: file, line: line)
        XCTAssertEqual(fixture.reader.selectedTextReadCount, 0, file: file, line: line)
        XCTAssertEqual(fixture.reader.fullValueReadCount, 0, file: file, line: line)
        XCTAssertEqual(fixture.reader.boundsReadCount, 0, file: file, line: line)
        XCTAssertEqual(fixture.sourceTextFactory.creationCount, 0, file: file, line: line)
    }
}

@MainActor
private struct AXCaptureFixture {
    let gateway: AccessibilityGateway
    let reader: AXCaptureReaderSpy
    let sourceTextFactory: SourceTextFactorySpy
}

private final class AXCaptureReaderSpy: AXCaptureReading, @unchecked Sendable {
    let capability: AXFocusedElementCapability
    var selectedRangeResult: Result<AXTextRange, DomainFailure> = .success(
        AXTextRange(location: 0, length: 0)
    )
    var selectedTextResult: Result<String, DomainFailure> = .success(
        "SYNTHETIC-001-selection"
    )
    var fullValueResult: Result<String, DomainFailure> = .success(
        "SYNTHETIC-001-whole-field"
    )
    var boundsResult: Result<CGRect?, DomainFailure> = .success(nil)

    private(set) var capabilityReadCount = 0
    private(set) var selectedRangeReadCount = 0
    private(set) var selectedTextReadCount = 0
    private(set) var fullValueReadCount = 0
    private(set) var boundsReadCount = 0

    init(capability: AXFocusedElementCapability) {
        self.capability = capability
    }

    func focusedElementCapability() -> Result<AXFocusedElementCapability, DomainFailure> {
        capabilityReadCount += 1
        return .success(capability)
    }

    func selectedTextRange() -> Result<AXTextRange, DomainFailure> {
        selectedRangeReadCount += 1
        return selectedRangeResult
    }

    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure> {
        selectedTextReadCount += 1
        return selectedTextResult
    }

    func fullValue() -> Result<String, DomainFailure> {
        fullValueReadCount += 1
        return fullValueResult
    }

    func bounds(for range: AXTextRange) -> Result<CGRect?, DomainFailure> {
        boundsReadCount += 1
        return boundsResult
    }
}

private final class SourceTextFactorySpy: AXSourceTextCreating, @unchecked Sendable {
    private(set) var createdValues: [String] = []

    var creationCount: Int {
        createdValues.count
    }

    func makeSourceText(_ value: String) -> SourceText {
        createdValues.append(value)
        return SourceText(value)
    }
}
