import Foundation
import XCTest

/// T-029: proves the synthetic AX host fixtures drive the real
/// `AccessibilityGateway` pipeline deterministically, using only
/// SYNTHETIC-001 content and never a real application.
final class SyntheticAXHostFixtureTests: XCTestCase {
    private let transformer = DeterministicTransformer()

    func testSelectionFixtureCapturesSelectedSyntheticText() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )

        let result = await gateway.capture(sessionID: InteractionSessionID())

        guard case .success(let captured) = result else {
            XCTFail("selection fixture must capture successfully")
            return
        }
        XCTAssertEqual(captured.sourceText.value, host.selectedSegment)
        XCTAssertEqual(
            captured.captureMode,
            .selectedText(host.reportedSelectedRange)
        )
        XCTAssertNotNil(captured.anchorRect)
    }

    func testWholeFieldFixtureFallsBackToFullValue() async {
        let host = SyntheticAXTextHost.wholeFieldFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )

        let result = await gateway.capture(sessionID: InteractionSessionID())

        guard case .success(let captured) = result else {
            XCTFail("whole-field fixture must capture successfully")
            return
        }
        XCTAssertEqual(captured.sourceText.value, host.fullText)
        XCTAssertEqual(captured.captureMode, .wholeField)
    }

    func testEmptyFixtureFailsWithEmptySource() async {
        let host = SyntheticAXTextHost.emptyFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )

        let result = await gateway.capture(sessionID: InteractionSessionID())

        guard case .failure(let failure) = result else {
            XCTFail("empty fixture must fail")
            return
        }
        XCTAssertEqual(failure, .emptySource)
    }

    func testReadOnlyFixtureFailsAsUnsupported() async {
        let host = SyntheticAXTextHost.readOnlyFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )

        let result = await gateway.capture(sessionID: InteractionSessionID())

        guard case .failure(let failure) = result else {
            XCTFail("read-only fixture must fail")
            return
        }
        XCTAssertEqual(failure, .unsupportedTarget)
        XCTAssertEqual(host.setterAttemptCount, 0)
    }

    func testSecureInputFixtureRefusesWithoutContentReads() async {
        let host = SyntheticAXTextHost.secureInputFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )

        let result = await gateway.capture(sessionID: InteractionSessionID())

        guard case .failure(let failure) = result else {
            XCTFail("secure-input fixture must fail")
            return
        }
        XCTAssertEqual(failure, .secureInputActive)
        XCTAssertEqual(host.contentReadCount, 0)
        XCTAssertEqual(host.setterAttemptCount, 0)
    }

    func testElementInvalidationBlocksAuthoritativeWrite() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        guard let snapshot = await captureSnapshot(host: host, gateway: gateway) else {
            return
        }

        host.invalidateElement()
        let result = await gateway.replaceAfterAuthoritativeValidation(snapshot)

        guard case .failure(let failure) = result else {
            XCTFail("invalidated element must block the write")
            return
        }
        XCTAssertEqual(failure, .invalidTarget)
        XCTAssertEqual(host.setterAttemptCount, 0)
        XCTAssertEqual(host.selectedSegment, snapshot.originalText.value)
    }

    func testWindowSwitchBlocksAuthoritativeWrite() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        guard let snapshot = await captureSnapshot(host: host, gateway: gateway) else {
            return
        }

        host.switchWindow()
        let result = await gateway.replaceAfterAuthoritativeValidation(snapshot)

        guard case .failure(let failure) = result else {
            XCTFail("switched window must block the write")
            return
        }
        XCTAssertEqual(failure, .invalidTarget)
        XCTAssertEqual(host.setterAttemptCount, 0)
    }

    func testControlledSetterFailureLeavesTextUnchanged() async {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        guard let snapshot = await captureSnapshot(host: host, gateway: gateway) else {
            return
        }
        let originalFullText = host.fullText

        host.failNextSetterAttempts(1)
        let failed = await gateway.replaceAfterAuthoritativeValidation(snapshot)

        guard case .failure(let failure) = failed else {
            XCTFail("forced setter failure must surface as writeFailed")
            return
        }
        XCTAssertEqual(failure, .writeFailed)
        XCTAssertEqual(host.setterAttemptCount, 1)
        XCTAssertEqual(host.fullText, originalFullText)

        let succeeded = await gateway.replaceAfterAuthoritativeValidation(snapshot)

        guard case .success = succeeded else {
            XCTFail("second attempt must succeed once the forced failure is consumed")
            return
        }
        XCTAssertEqual(host.setterAttemptCount, 2)
        XCTAssertEqual(host.selectedSegment, snapshot.transformedText.value)
    }

    func testEveryFixtureContentCarriesSyntheticMarker() {
        let nonEmptyFixtures: [SyntheticAXTextHost] = [
            .selectionFixture(),
            .wholeFieldFixture(),
            .readOnlyFixture(),
            .secureInputFixture(),
        ]
        for host in nonEmptyFixtures {
            XCTAssertTrue(
                host.fullText.contains(SyntheticAXTextHost.syntheticMarker),
                "synthetic host content must be labeled SYNTHETIC-001"
            )
        }
        XCTAssertTrue(SyntheticAXTextHost.emptyFixture().fullText.isEmpty)
    }

    private func captureSnapshot(
        host: SyntheticAXTextHost,
        gateway: AccessibilityGateway,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> AXWriteSnapshot? {
        let result = await gateway.capture(sessionID: InteractionSessionID())
        guard case .success(let captured) = result else {
            XCTFail("fixture capture must succeed", file: file, line: line)
            return nil
        }
        return AXWriteSnapshot(
            targetHandle: captured.targetHandle,
            pid: host.pid,
            captureMode: captured.captureMode,
            originalText: captured.sourceText,
            transformedText: transformer.transform(captured.sourceText)
        )
    }
}
