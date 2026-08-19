import Foundation
import XCTest

@MainActor
final class InteractionSessionCoordinatorTests: XCTestCase {
    private let original = SourceText("SYNTHETIC-001-original")
    private let transformed = TransformedText(value: "【系统交互验证】\nSYNTHETIC-001-original")

    func testDirectSessionTraversesTheCompleteApprovedStatePath() async {
        let fixture = makeFixture()

        XCTAssertEqual(fixture.coordinator.state, .idle)

        let sessionID = fixture.coordinator.beginDirectSession()
        fixture.coordinator.permissionResolved(granted: true, for: sessionID)
        fixture.coordinator.captureCompleted(
            source: original,
            transformed: transformed,
            mode: .wholeField,
            for: sessionID
        )

        XCTAssertEqual(
            Set(fixture.coordinator.availableActions),
            Set([.confirmReplacement, .copyResult, .cancel])
        )

        fixture.coordinator.confirmReplacement()
        await fixture.coordinator.applyWork?.value
        fixture.coordinator.close()

        XCTAssertEqual(
            fixture.observer.transitions,
            [
                .checkingPermission,
                .capturingTarget,
                .previewing(.ready),
                .applying,
                .recoverable,
                .ended,
            ]
        )
        XCTAssertEqual(fixture.target.replaceCount, 1)
        XCTAssertEqual(fixture.target.restoreCount, 0)
    }

    func testStartingANewSessionLeavesOnlyOneActiveSessionAndIgnoresOldCallbacks() {
        let fixture = makeFixture()
        let oldSessionID = fixture.coordinator.beginDirectSession()
        let currentSessionID = fixture.coordinator.beginDirectSession()

        XCTAssertNotEqual(oldSessionID, currentSessionID)
        XCTAssertEqual(fixture.coordinator.currentSessionID, currentSessionID)
        XCTAssertEqual(fixture.coordinator.state, .checkingPermission)

        fixture.coordinator.permissionResolved(granted: true, for: oldSessionID)
        fixture.coordinator.captureCompleted(
            source: original,
            transformed: transformed,
            mode: .wholeField,
            for: oldSessionID
        )

        XCTAssertEqual(fixture.coordinator.currentSessionID, currentSessionID)
        XCTAssertEqual(fixture.coordinator.state, .checkingPermission)
        XCTAssertEqual(fixture.target.directWriteCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)

        fixture.coordinator.permissionResolved(granted: true, for: currentSessionID)
        XCTAssertEqual(fixture.coordinator.state, .capturingTarget)
    }

    func testNoSetterRunsBeforeExplicitConfirmation() {
        let fixture = makeReadyDirectSession()

        XCTAssertEqual(fixture.coordinator.state, .previewing(.ready))
        XCTAssertEqual(fixture.target.directWriteCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testCancelPerformsNoWriteAndNoPasteboardAccess() {
        let fixture = makeReadyDirectSession()

        fixture.coordinator.cancel()

        XCTAssertEqual(fixture.coordinator.state, .ended)
        XCTAssertEqual(fixture.target.directWriteCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testClipboardInputNeverOffersOrPerformsDirectReplacement() async {
        let fixture = makeFixture()

        fixture.coordinator.beginClipboardSession(
            source: original,
            transformed: transformed
        )

        XCTAssertEqual(fixture.coordinator.state, .previewing(.ready))
        XCTAssertEqual(
            Set(fixture.coordinator.availableActions),
            Set([.copyResult, .cancel])
        )

        fixture.coordinator.confirmReplacement()
        await fixture.coordinator.applyWork?.value

        XCTAssertEqual(fixture.coordinator.state, .previewing(.ready))
        XCTAssertEqual(fixture.target.directWriteCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testFailedRecoveryValidationDisablesFurtherDirectWrites() async {
        let fixture = makeReadyDirectSession()
        fixture.coordinator.confirmReplacement()
        await fixture.coordinator.applyWork?.value
        XCTAssertEqual(fixture.coordinator.state, .recoverable)
        XCTAssertEqual(fixture.target.replaceCount, 1)

        fixture.target.recoveryIsValid = false
        fixture.coordinator.recoverOriginal()
        await fixture.coordinator.recoverWork?.value

        XCTAssertEqual(
            fixture.coordinator.state,
            .previewing(.recoveryUnavailable)
        )
        XCTAssertEqual(
            Set(fixture.coordinator.availableActions),
            Set([.copyOriginal, .close])
        )
        XCTAssertEqual(fixture.target.replaceCount, 1)
        XCTAssertEqual(fixture.target.restoreCount, 0)

        fixture.coordinator.confirmReplacement()
        await fixture.coordinator.applyWork?.value
        fixture.coordinator.recoverOriginal()
        await fixture.coordinator.recoverWork?.value

        XCTAssertEqual(fixture.target.replaceCount, 1)
        XCTAssertEqual(fixture.target.restoreCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 0)
    }

    func testRecoveryUnavailableOnlyCopiesOriginalOrCloses() async {
        let fixture = makeReadyDirectSession()
        fixture.coordinator.confirmReplacement()
        await fixture.coordinator.applyWork?.value
        fixture.target.recoveryIsValid = false
        fixture.coordinator.recoverOriginal()
        await fixture.coordinator.recoverWork?.value

        fixture.coordinator.copyOriginal()

        XCTAssertEqual(fixture.pasteboard.writeCount, 1)
        XCTAssertEqual(fixture.pasteboard.writtenValues, [original.value])
        XCTAssertEqual(fixture.target.replaceCount, 1)
        XCTAssertEqual(fixture.target.restoreCount, 0)

        fixture.coordinator.close()

        XCTAssertEqual(fixture.coordinator.state, .ended)
        XCTAssertEqual(fixture.target.replaceCount, 1)
        XCTAssertEqual(fixture.target.restoreCount, 0)
        XCTAssertEqual(fixture.pasteboard.writeCount, 1)
    }

    private func makeReadyDirectSession() -> Fixture {
        let fixture = makeFixture()
        let sessionID = fixture.coordinator.beginDirectSession()
        fixture.coordinator.permissionResolved(granted: true, for: sessionID)
        fixture.coordinator.captureCompleted(
            source: original,
            transformed: transformed,
            mode: .wholeField,
            for: sessionID
        )
        return fixture
    }

    private func makeFixture() -> Fixture {
        let target = SessionTextTargetSpy()
        let pasteboard = SessionPasteboardSpy()
        let observer = SessionStateObserverSpy()
        let coordinator = InteractionSessionCoordinator(
            target: target,
            pasteboard: pasteboard,
            observer: observer
        )
        return Fixture(
            coordinator: coordinator,
            target: target,
            pasteboard: pasteboard,
            observer: observer
        )
    }
}

@MainActor
private struct Fixture {
    let coordinator: InteractionSessionCoordinator
    let target: SessionTextTargetSpy
    let pasteboard: SessionPasteboardSpy
    let observer: SessionStateObserverSpy
}

private final class SessionTextTargetSpy: SessionTextTargetAccessing {
    private(set) var replaceCount = 0
    private(set) var restoreCount = 0
    var replacementSucceeds = true
    /// The failure reported when `replacementSucceeds` is false. Defaults to the
    /// attempted-write failure so existing scenarios keep their meaning.
    var replacementFailure: DomainFailure = .writeFailed
    var recoveryIsValid = true
    var restorationSucceeds = true

    var directWriteCount: Int {
        replaceCount + restoreCount
    }

    func replace(_ content: SessionContent) -> Result<Void, DomainFailure> {
        replaceCount += 1
        return replacementSucceeds ? .success(()) : .failure(replacementFailure)
    }

    func validateForRecovery(_ content: SessionContent) -> Bool {
        recoveryIsValid
    }

    func restore(_ content: SessionContent) -> Bool {
        restoreCount += 1
        return restorationSucceeds
    }
}

private final class SessionPasteboardSpy: SessionPasteboardAccessing {
    private(set) var writtenValues: [String] = []

    var writeCount: Int {
        writtenValues.count
    }

    func writeLocalStringAfterExplicitAction(_ text: String) -> Bool {
        writtenValues.append(text)
        return true
    }
}

private final class SessionStateObserverSpy: SessionStateObserving {
    private(set) var transitions: [InteractionSessionState] = []

    func sessionCoordinatorDidTransition(to state: InteractionSessionState) {
        transitions.append(state)
    }
}
