import AppKit
import ApplicationServices

enum AccessibilityPermissionStatus: Equatable {
    case authorized
    case notAuthorized
}

enum AccessibilityPermissionFlowState: Equatable {
    case idle
    case authorized
    case permissionRequired
    case accessibilitySettingsOpened
    case privacyAndSecuritySettingsOpened
}

@MainActor
protocol AccessibilityPermissionChecking: AnyObject {
    func currentStatus() -> AccessibilityPermissionStatus
}

@MainActor
protocol AccessibilitySettingsOpening: AnyObject {
    func openAccessibilitySettings() -> Bool
    func openPrivacyAndSecuritySettings() -> Bool
}

@MainActor
protocol PermissionProtectedTextAccessing: AnyObject {
    func beginProtectedRead()
    func beginProtectedWrite()
}

@MainActor
protocol ExplicitClipboardInputStarting: AnyObject {
    func startClipboardInputAfterExplicitAction()
}

@MainActor
final class AccessibilityPermissionFlow {
    private let permission: AccessibilityPermissionChecking
    private let settings: AccessibilitySettingsOpening
    private let protectedText: PermissionProtectedTextAccessing
    private let clipboardInput: ExplicitClipboardInputStarting

    private(set) var state: AccessibilityPermissionFlowState = .idle

    init(
        permission: AccessibilityPermissionChecking,
        settings: AccessibilitySettingsOpening,
        protectedText: PermissionProtectedTextAccessing,
        clipboardInput: ExplicitClipboardInputStarting
    ) {
        self.permission = permission
        self.settings = settings
        self.protectedText = protectedText
        self.clipboardInput = clipboardInput
    }

    func beginCapture() {
        if permission.currentStatus() == .authorized {
            state = .authorized
            protectedText.beginProtectedRead()
        } else {
            state = .permissionRequired
        }
    }

    func requestProtectedWriteAfterExplicitConfirmation() {
        if permission.currentStatus() == .authorized {
            state = .authorized
            protectedText.beginProtectedWrite()
        } else {
            state = .permissionRequired
        }
    }

    func recheckAfterExplicitAction() {
        beginCapture()
    }

    func openSettingsAfterExplicitAction() {
        guard state != .authorized else {
            return
        }

        if settings.openAccessibilitySettings() {
            state = .accessibilitySettingsOpened
        } else if settings.openPrivacyAndSecuritySettings() {
            state = .privacyAndSecuritySettingsOpened
        } else {
            state = .permissionRequired
        }
    }

    func startClipboardInputAfterExplicitAction() {
        guard state != .authorized else {
            return
        }
        clipboardInput.startClipboardInputAfterExplicitAction()
    }
}

@MainActor
final class SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .authorized : .notAuthorized
    }
}

@MainActor
final class SystemAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    private enum Destination {
        static let accessibility = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        static let privacyAndSecurity = URL(
            string: "x-apple.systempreferences:com.apple.preference.security"
        )
    }

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openAccessibilitySettings() -> Bool {
        guard let url = Destination.accessibility else {
            return false
        }
        return workspace.open(url)
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        guard let url = Destination.privacyAndSecurity else {
            return false
        }
        return workspace.open(url)
    }
}
