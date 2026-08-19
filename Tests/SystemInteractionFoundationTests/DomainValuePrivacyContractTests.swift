import Foundation
import XCTest

final class DeterministicTransformerTests: XCTestCase {
    private let marker = "【系统交互验证】\n"

    func testRepresentativeInputsArePreservedCharacterForCharacter() {
        let inputs = [
            "SYNTHETIC-001-中文",
            "SYNTHETIC-001-English",
            "SYNTHETIC-001-中英-mixed",
            " \t\n  ",
            "SYNTHETIC-001-line-1\nline-2\r\nline-3",
            "SYNTHETIC-001-🙂-♜-©-e\u{301}-<>&\\\"'",
        ]

        for input in inputs {
            assertExactTransformation(of: input)
        }
    }

    func testTenThousandCharacterInputIsPreservedWithoutTruncation() {
        let unit = "界A🙂\n"
        let input = String(String(repeating: unit, count: 2_500).prefix(10_000))

        XCTAssertEqual(input.count, 10_000)
        assertExactTransformation(of: input)
    }

    private func assertExactTransformation(
        of input: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = SourceText(input)
        let result = DeterministicTransformer().transform(source)

        XCTAssertEqual(
            result.value,
            marker + input,
            "The marker may be added, but every source character must remain unchanged",
            file: file,
            line: line
        )
        XCTAssertEqual(
            String(result.value.dropFirst(marker.count)),
            input,
            file: file,
            line: line
        )
    }
}

final class ErrorMappingTests: XCTestCase {
    func testEveryKnownFailureHasUnderstandableCopyAndASafeNextAction() {
        let cases: [(DomainFailure, RecoveryAction)] = [
            (.hotKeyConflict, .retryRegistration),
            (.accessibilityPermissionRequired, .openSettings),
            (.secureInputActive, .close),
            (.emptySource, .retry),
            (.unsupportedTarget, .useClipboard),
            (.axTimedOut, .retry),
            (.axCannotComplete, .useClipboard),
            (.invalidTarget, .copyResult),
            (.sourceChanged, .retry),
            (.attributeNotSettable, .copyResult),
            (.writeFailed, .copyResult),
            (.recoveryTargetChanged, .copyOriginal),
            (.pasteboardReadFailed, .retry),
            (.pasteboardWriteFailed, .retry),
            (.panelPlacementFallback, .continueWithoutPrecisePlacement),
        ]
        let mapper = DomainFailureMapper()

        for (failure, expectedAction) in cases {
            let presentation = mapper.presentation(for: failure)

            XCTAssertFalse(presentation.message.isEmpty)
            XCTAssertTrue(presentation.safeNextActions.contains(expectedAction))
            XCTAssertFalse(presentation.message.contains("AXError"))
            XCTAssertFalse(presentation.message.contains("OSStatus"))
            XCTAssertFalse(presentation.message.contains("SYNTHETIC-001"))
        }
    }

    func testUnknownFailureIsFailClosedWithoutRawCodes() {
        let presentation = DomainFailureMapper().presentation(for: .unknown)

        XCTAssertTrue(presentation.isFailClosed)
        XCTAssertFalse(presentation.message.isEmpty)
        XCTAssertFalse(presentation.safeNextActions.isEmpty)
        XCTAssertFalse(presentation.message.contains("-25205"))
        XCTAssertFalse(presentation.message.contains("SYNTHETIC-001"))
    }
}

final class PrivacyContractTests: XCTestCase {
    func testSensitiveDomainValuesAreNotCodable() {
        assertIsNotCodable(SourceText.self)
        assertIsNotCodable(TransformedText.self)
        assertIsNotCodable(TargetSnapshot.self)
        assertIsNotCodable(RecoverySnapshot.self)
    }

    func testDomainFailuresDoNotCarrySensitiveStrings() {
        let failures: [DomainFailure] = [
            .hotKeyConflict,
            .accessibilityPermissionRequired,
            .secureInputActive,
            .emptySource,
            .unsupportedTarget,
            .axTimedOut,
            .axCannotComplete,
            .invalidTarget,
            .sourceChanged,
            .attributeNotSettable,
            .writeFailed,
            .recoveryTargetChanged,
            .pasteboardReadFailed,
            .pasteboardWriteFailed,
            .panelPlacementFallback,
            .unknown,
        ]

        for failure in failures {
            XCTAssertFalse(containsStringStorage(failure))
            XCTAssertFalse(String(describing: failure).contains("SYNTHETIC-001"))
        }
    }

    func testLogEventsAcceptCategoriesButContainNoTextStorage() {
        let event = PrivacySafeLogEvent(
            category: .domainFailure,
            state: .previewing,
            failure: .writeFailed
        )

        XCTAssertFalse(containsStringStorage(event))
        XCTAssertFalse(String(describing: event).contains("SYNTHETIC-001"))
    }

    private func assertIsNotCodable<T>(
        _ type: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(type is any Encodable.Type, file: file, line: line)
        XCTAssertFalse(type is any Decodable.Type, file: file, line: line)
    }

    private func containsStringStorage(_ value: Any) -> Bool {
        if value is String || value is Substring {
            return true
        }

        return Mirror(reflecting: value).children.contains { child in
            containsStringStorage(child.value)
        }
    }
}
