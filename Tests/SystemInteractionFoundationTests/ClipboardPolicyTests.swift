import XCTest

@MainActor
final class ClipboardPolicyTests: XCTestCase {
    private let source = SourceText("SYNTHETIC-001-clipboard-original")
    private let result = TransformedText(
        value: "【系统交互验证】\nSYNTHETIC-001-clipboard-original"
    )

    func testCancelPerformsZeroPasteboardReadsAndWrites() {
        let fixture = makeFixture()
        fixture.policy.ordinaryPreviewDidAppear()

        fixture.policy.cancel()

        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testOrdinaryPreviewPerformsZeroPasteboardReadsAndWrites() {
        let fixture = makeFixture()

        fixture.policy.ordinaryPreviewDidAppear()

        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testSecureInputRefusalPerformsZeroPasteboardReadsAndWrites() {
        let fixture = makeFixture()

        fixture.policy.secureInputWasRejected()

        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testExplicitClipboardInputReadsExactlyOnce() {
        let fixture = makeFixture()
        fixture.pasteboard.nextReadValue = source.value

        let value = fixture.policy.readFromClipboardAfterExplicitAction()

        XCTAssertEqual(value, source.value)
        XCTAssertEqual(fixture.pasteboard.readCount, 1)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testExplicitCopyResultWritesExactlyOnceWithCurrentHostOnly() {
        let fixture = makeFixture()

        fixture.policy.copyResultAfterExplicitAction(result)

        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 1)
        XCTAssertEqual(
            fixture.pasteboard.writes,
            [
                PasteboardWriteSpy.Record(
                    value: result.value,
                    privacy: .currentHostOnly
                )
            ]
        )
    }

    func testExplicitCopyOriginalWritesExactlyOnceWithCurrentHostOnly() {
        let fixture = makeFixture()

        fixture.policy.copyOriginalAfterExplicitAction(source)

        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 1)
        XCTAssertEqual(
            fixture.pasteboard.writes,
            [
                PasteboardWriteSpy.Record(
                    value: source.value,
                    privacy: .currentHostOnly
                )
            ]
        )
    }

    private func makeFixture() -> ClipboardPolicyFixture {
        let pasteboard = PasteboardWriteSpy()
        let policy = ClipboardPolicy(pasteboard: pasteboard)
        return ClipboardPolicyFixture(policy: policy, pasteboard: pasteboard)
    }
}

@MainActor
private struct ClipboardPolicyFixture {
    let policy: ClipboardPolicy
    let pasteboard: PasteboardWriteSpy
}

private final class PasteboardWriteSpy: PasteboardAccessing {
    struct Record: Equatable {
        let value: String
        let privacy: PasteboardWritePrivacy
    }

    var nextReadValue: String?
    private(set) var readCount = 0
    private(set) var writes: [Record] = []

    var writeCount: Int {
        writes.count
    }

    func readStringAfterExplicitAction() -> String? {
        readCount += 1
        return nextReadValue
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        writes.append(Record(value: value, privacy: privacy))
        return true
    }
}
