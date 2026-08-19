import XCTest

@MainActor
final class AccessibilityPermissionFlowTests: XCTestCase {
    func testAuthorizedPermissionStartsProtectedRead() {
        let fixture = makeFixture(status: .authorized)

        fixture.flow.beginCapture()

        XCTAssertEqual(fixture.flow.state, .authorized)
        XCTAssertEqual(fixture.protectedText.readCount, 1)
        XCTAssertEqual(fixture.protectedText.writeCount, 0)
        XCTAssertEqual(fixture.clipboard.startCount, 0)
    }

    func testUnauthorizedPermissionShowsRequiredStateWithoutProtectedAccess() {
        let fixture = makeFixture(status: .notAuthorized)

        fixture.flow.beginCapture()

        XCTAssertEqual(fixture.flow.state, .permissionRequired)
        XCTAssertEqual(fixture.protectedText.readCount, 0)
        XCTAssertEqual(fixture.protectedText.writeCount, 0)
        XCTAssertEqual(fixture.settings.accessibilityOpenCount, 0)
        XCTAssertEqual(fixture.settings.privacyAndSecurityOpenCount, 0)
        XCTAssertEqual(fixture.clipboard.startCount, 0)
    }

    func testExplicitOpenSettingsUsesAccessibilityDestinationWhenAvailable() {
        let fixture = makeFixture(status: .notAuthorized)
        fixture.settings.accessibilityOpenSucceeds = true
        fixture.flow.beginCapture()

        fixture.flow.openSettingsAfterExplicitAction()

        XCTAssertEqual(fixture.settings.accessibilityOpenCount, 1)
        XCTAssertEqual(fixture.settings.privacyAndSecurityOpenCount, 0)
        XCTAssertEqual(fixture.flow.state, .accessibilitySettingsOpened)
        XCTAssertEqual(fixture.protectedText.totalAccessCount, 0)
    }

    func testExplicitOpenSettingsFallsBackToPrivacyAndSecurity() {
        let fixture = makeFixture(status: .notAuthorized)
        fixture.settings.accessibilityOpenSucceeds = false
        fixture.settings.privacyAndSecurityOpenSucceeds = true
        fixture.flow.beginCapture()

        fixture.flow.openSettingsAfterExplicitAction()

        XCTAssertEqual(fixture.settings.accessibilityOpenCount, 1)
        XCTAssertEqual(fixture.settings.privacyAndSecurityOpenCount, 1)
        XCTAssertEqual(fixture.flow.state, .privacyAndSecuritySettingsOpened)
        XCTAssertEqual(fixture.protectedText.totalAccessCount, 0)
    }

    func testExplicitRecheckContinuesCaptureAfterPermissionIsGranted() {
        let fixture = makeFixture(status: .notAuthorized)
        fixture.flow.beginCapture()
        XCTAssertEqual(fixture.protectedText.readCount, 0)

        fixture.permission.status = .authorized
        fixture.flow.recheckAfterExplicitAction()

        XCTAssertEqual(fixture.permission.checkCount, 2)
        XCTAssertEqual(fixture.flow.state, .authorized)
        XCTAssertEqual(fixture.protectedText.readCount, 1)
        XCTAssertEqual(fixture.protectedText.writeCount, 0)
        XCTAssertEqual(fixture.clipboard.startCount, 0)
    }

    func testMissingPermissionBlocksBothProtectedReadAndWrite() {
        let fixture = makeFixture(status: .notAuthorized)

        fixture.flow.beginCapture()
        fixture.flow.requestProtectedWriteAfterExplicitConfirmation()
        fixture.flow.recheckAfterExplicitAction()

        XCTAssertEqual(fixture.flow.state, .permissionRequired)
        XCTAssertEqual(fixture.protectedText.readCount, 0)
        XCTAssertEqual(fixture.protectedText.writeCount, 0)
        XCTAssertEqual(fixture.protectedText.totalAccessCount, 0)
        XCTAssertEqual(fixture.clipboard.startCount, 0)
    }

    func testClipboardInputStartsOnlyAfterExplicitUserAction() {
        let fixture = makeFixture(status: .notAuthorized)
        fixture.flow.beginCapture()

        XCTAssertEqual(fixture.clipboard.startCount, 0)

        fixture.flow.startClipboardInputAfterExplicitAction()

        XCTAssertEqual(fixture.clipboard.startCount, 1)
        XCTAssertEqual(fixture.protectedText.totalAccessCount, 0)
    }

    private func makeFixture(
        status: AccessibilityPermissionStatus
    ) -> PermissionFixture {
        let permission = AccessibilityPermissionSpy(status: status)
        let settings = AccessibilitySettingsSpy()
        let protectedText = PermissionProtectedTextSpy()
        let clipboard = ExplicitClipboardInputSpy()
        let flow = AccessibilityPermissionFlow(
            permission: permission,
            settings: settings,
            protectedText: protectedText,
            clipboardInput: clipboard
        )
        return PermissionFixture(
            flow: flow,
            permission: permission,
            settings: settings,
            protectedText: protectedText,
            clipboard: clipboard
        )
    }
}

@MainActor
private struct PermissionFixture {
    let flow: AccessibilityPermissionFlow
    let permission: AccessibilityPermissionSpy
    let settings: AccessibilitySettingsSpy
    let protectedText: PermissionProtectedTextSpy
    let clipboard: ExplicitClipboardInputSpy
}

private final class AccessibilityPermissionSpy: AccessibilityPermissionChecking {
    var status: AccessibilityPermissionStatus
    private(set) var checkCount = 0

    init(status: AccessibilityPermissionStatus) {
        self.status = status
    }

    func currentStatus() -> AccessibilityPermissionStatus {
        checkCount += 1
        return status
    }
}

private final class AccessibilitySettingsSpy: AccessibilitySettingsOpening {
    var accessibilityOpenSucceeds = true
    var privacyAndSecurityOpenSucceeds = true
    private(set) var accessibilityOpenCount = 0
    private(set) var privacyAndSecurityOpenCount = 0

    func openAccessibilitySettings() -> Bool {
        accessibilityOpenCount += 1
        return accessibilityOpenSucceeds
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        privacyAndSecurityOpenCount += 1
        return privacyAndSecurityOpenSucceeds
    }
}

private final class PermissionProtectedTextSpy: PermissionProtectedTextAccessing {
    private(set) var readCount = 0
    private(set) var writeCount = 0

    var totalAccessCount: Int {
        readCount + writeCount
    }

    func beginProtectedRead() {
        readCount += 1
    }

    func beginProtectedWrite() {
        writeCount += 1
    }
}

private final class ExplicitClipboardInputSpy: ExplicitClipboardInputStarting {
    private(set) var startCount = 0

    func startClipboardInputAfterExplicitAction() {
        startCount += 1
    }
}
