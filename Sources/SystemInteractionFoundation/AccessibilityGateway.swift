import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin
import Foundation

typealias TargetHandle = UUID

struct AXTextRange: Equatable, Sendable {
    let location: Int
    let length: Int
}

enum AXFocusedElementCapability: Equatable, Sendable {
    case editable
    case secure
    case readOnly
    case unsupported
}

struct AXCapturedTarget: Equatable, Sendable {
    let sessionID: InteractionSessionID
    let targetHandle: TargetHandle
    let sourceText: SourceText
    let captureMode: CaptureMode
    let anchorRect: CGRect?
}

protocol AXSourceTextCreating: Sendable {
    func makeSourceText(_ value: String) -> SourceText
}

struct DefaultAXSourceTextFactory: AXSourceTextCreating {
    func makeSourceText(_ value: String) -> SourceText {
        SourceText(value)
    }
}

protocol AXCaptureReading: Sendable {
    func focusedElementCapability() -> Result<AXFocusedElementCapability, DomainFailure>
    func selectedTextRange() -> Result<AXTextRange, DomainFailure>
    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure>
    func fullValue() -> Result<String, DomainFailure>
    func bounds(for range: AXTextRange) -> Result<CGRect?, DomainFailure>
    func retainedTargetReference() -> AXTargetReference?
}

protocol AXAuthoritativeTargetAccessing: Sendable {
    func isTargetApplicationRunning(expectedPID: Int32) -> Bool
    func currentExternalApplicationPID() -> Int32?
    func windowIdentityMatches(targetHandle: TargetHandle) -> Bool
    func elementIdentityMatches(targetHandle: TargetHandle) -> Bool
    func currentElementCapability() -> AXFocusedElementCapability
    func isGlobalSecureInputActive() -> Bool
    func selectedTextRange() -> Result<AXTextRange, DomainFailure>
    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure>
    func fullValue() -> Result<String, DomainFailure>
    func isReplacementAttributeSettable(for mode: CaptureMode) -> Bool
    func setSelectedText(_ value: String) -> Bool
    func setWholeValue(_ value: String) -> Bool
}

struct AXWriteSnapshot: Sendable {
    let targetHandle: TargetHandle
    let pid: Int32
    let captureMode: CaptureMode
    let originalText: SourceText
    let transformedText: TransformedText
}

struct AXRecoveryContext: Sendable {
    let targetHandle: TargetHandle
    let pid: Int32
    let captureMode: CaptureMode
    let originalText: SourceText
    let expectedTransformedText: TransformedText
}

extension AXCaptureReading {
    func retainedTargetReference() -> AXTargetReference? {
        nil
    }
}

final class AXTargetReference: @unchecked Sendable {
    fileprivate let element: AXUIElement
    fileprivate let window: AXUIElement?
    fileprivate let pid: Int32

    fileprivate init(element: AXUIElement, window: AXUIElement?, pid: Int32) {
        self.element = element
        self.window = window
        self.pid = pid
    }
}

actor AccessibilityGateway {
    private let captureReader: any AXCaptureReading
    private let sourceTextFactory: any AXSourceTextCreating
    private let authoritativeTarget: (any AXAuthoritativeTargetAccessing)?
    private var targetReferences: [TargetHandle: AXTargetReference] = [:]

    init(
        captureReader: any AXCaptureReading,
        sourceTextFactory: any AXSourceTextCreating = DefaultAXSourceTextFactory(),
        authoritativeTarget: (any AXAuthoritativeTargetAccessing)? = nil
    ) {
        self.captureReader = captureReader
        self.sourceTextFactory = sourceTextFactory
        self.authoritativeTarget = authoritativeTarget
    }

    func capture(
        sessionID: InteractionSessionID
    ) -> Result<AXCapturedTarget, DomainFailure> {
        let capability: AXFocusedElementCapability
        switch captureReader.focusedElementCapability() {
        case .success(let value):
            capability = value
        case .failure(let failure):
            return .failure(failure)
        }

        switch capability {
        case .secure:
            return .failure(.secureInputActive)
        case .readOnly, .unsupported:
            return .failure(.unsupportedTarget)
        case .editable:
            break
        }

        let selectedRange: AXTextRange
        switch captureReader.selectedTextRange() {
        case .success(let value):
            selectedRange = value
        case .failure(let failure):
            return .failure(failure)
        }

        let sourceValue: String
        let captureMode: CaptureMode
        if selectedRange.length > 0 {
            switch captureReader.selectedText(in: selectedRange) {
            case .success(let value):
                sourceValue = value
            case .failure(let failure):
                return .failure(failure)
            }
            captureMode = .selectedText(selectedRange)
        } else {
            switch captureReader.fullValue() {
            case .success(let value):
                sourceValue = value
            case .failure(let failure):
                return .failure(failure)
            }
            captureMode = .wholeField
        }

        guard !sourceValue.isEmpty else {
            return .failure(.emptySource)
        }

        let anchorRect: CGRect?
        switch captureReader.bounds(for: selectedRange) {
        case .success(let value):
            anchorRect = value
        case .failure:
            anchorRect = nil
        }

        let targetHandle = TargetHandle()
        if let reference = captureReader.retainedTargetReference() {
            targetReferences[targetHandle] = reference
        }

        return .success(
            AXCapturedTarget(
                sessionID: sessionID,
                targetHandle: targetHandle,
                sourceText: sourceTextFactory.makeSourceText(sourceValue),
                captureMode: captureMode,
                anchorRect: anchorRect
            )
        )
    }

    func replaceAfterAuthoritativeValidation(
        _ snapshot: AXWriteSnapshot
    ) -> Result<AXRecoveryContext, DomainFailure> {
        guard snapshot.captureMode != .clipboardInput else {
            return .failure(.unsupportedTarget)
        }

        switch validate(
            targetHandle: snapshot.targetHandle,
            pid: snapshot.pid,
            mode: snapshot.captureMode,
            expectedText: snapshot.originalText.value,
            isRecovery: false
        ) {
        case .success:
            break
        case .failure(let failure):
            return .failure(failure)
        }

        guard setText(
            snapshot.transformedText.value,
            mode: snapshot.captureMode,
            targetHandle: snapshot.targetHandle
        ) else {
            return .failure(.writeFailed)
        }

        return .success(
            AXRecoveryContext(
                targetHandle: snapshot.targetHandle,
                pid: snapshot.pid,
                captureMode: snapshot.captureMode,
                originalText: snapshot.originalText,
                expectedTransformedText: snapshot.transformedText
            )
        )
    }

    func restoreAfterAuthoritativeValidation(
        _ recovery: AXRecoveryContext
    ) -> Result<Void, DomainFailure> {
        guard recovery.captureMode != .clipboardInput else {
            return .failure(.recoveryTargetChanged)
        }

        switch validate(
            targetHandle: recovery.targetHandle,
            pid: recovery.pid,
            mode: recovery.captureMode,
            expectedText: recovery.expectedTransformedText.value,
            isRecovery: true
        ) {
        case .success:
            break
        case .failure(let failure):
            return .failure(failure)
        }

        guard setText(
            recovery.originalText.value,
            mode: recovery.captureMode,
            targetHandle: recovery.targetHandle
        ) else {
            return .failure(.recoveryTargetChanged)
        }
        return .success(())
    }

    private func validate(
        targetHandle: TargetHandle,
        pid: Int32,
        mode: CaptureMode,
        expectedText: String,
        isRecovery: Bool
    ) -> Result<Void, DomainFailure> {
        guard targetApplicationIsRunning(pid: pid) else {
            return .failure(.invalidTarget)
        }
        guard currentExternalPID() == pid else {
            return .failure(.invalidTarget)
        }
        guard windowMatches(targetHandle: targetHandle) else {
            return .failure(.invalidTarget)
        }
        guard elementMatches(targetHandle: targetHandle) else {
            return .failure(.invalidTarget)
        }

        switch elementCapability(targetHandle: targetHandle) {
        case .editable:
            break
        case .secure:
            return .failure(.secureInputActive)
        case .readOnly:
            return .failure(.attributeNotSettable)
        case .unsupported:
            return .failure(.unsupportedTarget)
        }

        guard !globalSecureInputIsActive() else {
            return .failure(.secureInputActive)
        }

        let contentFailure: DomainFailure = isRecovery
            ? .recoveryTargetChanged
            : .sourceChanged
        switch currentText(mode: mode, targetHandle: targetHandle) {
        case .success(let currentText):
            guard currentText == expectedText else {
                return .failure(contentFailure)
            }
        case .failure(let failure):
            return .failure(isRecovery ? .recoveryTargetChanged : failure)
        }

        guard replacementAttributeIsSettable(
            mode: mode,
            targetHandle: targetHandle
        ) else {
            return .failure(.attributeNotSettable)
        }
        return .success(())
    }

    private func currentText(
        mode: CaptureMode,
        targetHandle: TargetHandle
    ) -> Result<String, DomainFailure> {
        switch mode {
        case .selectedText(let expectedRange):
            switch currentSelectedRange(targetHandle: targetHandle) {
            case .success(let currentRange):
                guard currentRange == expectedRange else {
                    return .failure(.sourceChanged)
                }
            case .failure(let failure):
                return .failure(failure)
            }
            return selectedText(
                in: expectedRange,
                targetHandle: targetHandle
            )
        case .wholeField:
            return wholeValue(targetHandle: targetHandle)
        case .clipboardInput:
            return .failure(.unsupportedTarget)
        }
    }

    private func targetApplicationIsRunning(pid: Int32) -> Bool {
        if let authoritativeTarget {
            return authoritativeTarget.isTargetApplicationRunning(expectedPID: pid)
        }
        guard targetReferences.values.contains(where: { $0.pid == pid }) else {
            return false
        }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func currentExternalPID() -> Int32? {
        if let authoritativeTarget {
            return authoritativeTarget.currentExternalApplicationPID()
        }
        guard
            case .success(let value) = copyAttribute(
                kAXFocusedApplicationAttribute,
                from: AXUIElementCreateSystemWide()
            ),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        var pid: pid_t = 0
        let application = unsafeDowncast(value, to: AXUIElement.self)
        return AXUIElementGetPid(application, &pid) == .success ? pid : nil
    }

    private func windowMatches(targetHandle: TargetHandle) -> Bool {
        if let authoritativeTarget {
            return authoritativeTarget.windowIdentityMatches(targetHandle: targetHandle)
        }
        guard
            let target = targetReferences[targetHandle],
            let expectedWindow = target.window,
            let currentElement = currentFocusedElement(),
            case .success(let value) = copyAttribute(
                kAXWindowAttribute,
                from: currentElement
            ),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return false
        }
        return CFEqual(expectedWindow, unsafeDowncast(value, to: AXUIElement.self))
    }

    private func elementMatches(targetHandle: TargetHandle) -> Bool {
        if let authoritativeTarget {
            return authoritativeTarget.elementIdentityMatches(targetHandle: targetHandle)
        }
        guard
            let expectedElement = targetReferences[targetHandle]?.element,
            let currentElement = currentFocusedElement()
        else {
            return false
        }
        return CFEqual(expectedElement, currentElement)
    }

    private func elementCapability(
        targetHandle: TargetHandle
    ) -> AXFocusedElementCapability {
        if let authoritativeTarget {
            return authoritativeTarget.currentElementCapability()
        }
        guard let element = targetReferences[targetHandle]?.element else {
            return .unsupported
        }
        return capability(of: element)
    }

    private func globalSecureInputIsActive() -> Bool {
        authoritativeTarget?.isGlobalSecureInputActive()
            ?? IsSecureEventInputEnabled()
    }

    private func currentSelectedRange(
        targetHandle: TargetHandle
    ) -> Result<AXTextRange, DomainFailure> {
        if let authoritativeTarget {
            return authoritativeTarget.selectedTextRange()
        }
        guard let element = targetReferences[targetHandle]?.element else {
            return .failure(.invalidTarget)
        }
        return selectedRange(of: element)
    }

    private func selectedText(
        in range: AXTextRange,
        targetHandle: TargetHandle
    ) -> Result<String, DomainFailure> {
        if let authoritativeTarget {
            return authoritativeTarget.selectedText(in: range)
        }
        guard let element = targetReferences[targetHandle]?.element else {
            return .failure(.invalidTarget)
        }
        return copyString(kAXSelectedTextAttribute, from: element)
    }

    private func wholeValue(
        targetHandle: TargetHandle
    ) -> Result<String, DomainFailure> {
        if let authoritativeTarget {
            return authoritativeTarget.fullValue()
        }
        guard let element = targetReferences[targetHandle]?.element else {
            return .failure(.invalidTarget)
        }
        return copyString(kAXValueAttribute, from: element)
    }

    private func replacementAttributeIsSettable(
        mode: CaptureMode,
        targetHandle: TargetHandle
    ) -> Bool {
        if let authoritativeTarget {
            return authoritativeTarget.isReplacementAttributeSettable(for: mode)
        }
        guard let element = targetReferences[targetHandle]?.element else {
            return false
        }
        switch mode {
        case .selectedText:
            return attributeIsSettable(kAXSelectedTextAttribute, on: element) == true
        case .wholeField:
            return attributeIsSettable(kAXValueAttribute, on: element) == true
        case .clipboardInput:
            return false
        }
    }

    private func setText(
        _ value: String,
        mode: CaptureMode,
        targetHandle: TargetHandle
    ) -> Bool {
        if let authoritativeTarget {
            switch mode {
            case .selectedText:
                return authoritativeTarget.setSelectedText(value)
            case .wholeField:
                return authoritativeTarget.setWholeValue(value)
            case .clipboardInput:
                return false
            }
        }
        guard let element = targetReferences[targetHandle]?.element else {
            return false
        }
        let attribute: String
        switch mode {
        case .selectedText:
            attribute = kAXSelectedTextAttribute
        case .wholeField:
            attribute = kAXValueAttribute
        case .clipboardInput:
            return false
        }
        return AXUIElementSetAttributeValue(
            element,
            attribute as CFString,
            value as CFTypeRef
        ) == .success
    }

    private func currentFocusedElement() -> AXUIElement? {
        guard
            case .success(let value) = copyAttribute(
                kAXFocusedUIElementAttribute,
                from: AXUIElementCreateSystemWide()
            ),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func capability(of element: AXUIElement) -> AXFocusedElementCapability {
        if case .success(let value) = copyAttribute(kAXSubroleAttribute, from: element),
            value as? String == kAXSecureTextFieldSubrole
        {
            return .secure
        }
        if attributeIsSettable(kAXSelectedTextAttribute, on: element) == true
            || attributeIsSettable(kAXValueAttribute, on: element) == true
        {
            return .editable
        }
        let role: String?
        if case .success(let value) = copyAttribute(kAXRoleAttribute, from: element) {
            role = value as? String
        } else {
            role = nil
        }
        let textRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        return textRoles.contains(role ?? "") ? .readOnly : .unsupported
    }

    private func selectedRange(
        of element: AXUIElement
    ) -> Result<AXTextRange, DomainFailure> {
        switch copyAttribute(kAXSelectedTextRangeAttribute, from: element) {
        case .success(let value):
            guard CFGetTypeID(value) == AXValueGetTypeID() else {
                return .failure(.unsupportedTarget)
            }
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var range = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &range) else {
                return .failure(.unsupportedTarget)
            }
            return .success(
                AXTextRange(
                    location: max(0, range.location),
                    length: max(0, range.length)
                )
            )
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func copyString(
        _ attribute: String,
        from element: AXUIElement
    ) -> Result<String, DomainFailure> {
        switch copyAttribute(attribute, from: element) {
        case .success(let value):
            guard let string = value as? String else {
                return .failure(.unsupportedTarget)
            }
            return .success(string)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func copyAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> Result<CFTypeRef, DomainFailure> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        guard error == .success, let value else {
            return .failure(mapAXError(error))
        }
        return .success(value)
    }

    private func attributeIsSettable(
        _ attribute: String,
        on element: AXUIElement
    ) -> Bool? {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        ) == .success else {
            return nil
        }
        return settable.boolValue
    }

    private func mapAXError(_ error: AXError) -> DomainFailure {
        switch error {
        case .apiDisabled:
            return .accessibilityPermissionRequired
        case .cannotComplete:
            return .axCannotComplete
        case .invalidUIElement, .invalidUIElementObserver:
            return .invalidTarget
        case .attributeUnsupported, .noValue:
            return .unsupportedTarget
        default:
            return .unknown
        }
    }
}

final class SystemAXCaptureReader: AXCaptureReading, @unchecked Sendable {
    private var focusedElement: AXUIElement?
    private var focusedWindow: AXUIElement?
    private var focusedPID: Int32?

    func focusedElementCapability() -> Result<AXFocusedElementCapability, DomainFailure> {
        focusedElement = nil
        focusedWindow = nil
        focusedPID = nil
        let systemWide = AXUIElementCreateSystemWide()
        let elementResult = copyAttribute(
            kAXFocusedUIElementAttribute,
            from: systemWide
        )

        let element: AXUIElement
        switch elementResult {
        case .success(let value):
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return .failure(.unsupportedTarget)
            }
            element = unsafeDowncast(value, to: AXUIElement.self)
            focusedElement = element
        case .failure(let failure):
            return .failure(failure)
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return .failure(.invalidTarget)
        }
        focusedPID = pid

        if case .success(let value) = copyAttribute(kAXWindowAttribute, from: element),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        {
            focusedWindow = unsafeDowncast(value, to: AXUIElement.self)
        }

        switch copyAttribute(kAXSubroleAttribute, from: element) {
        case .success(let value):
            if value as? String == kAXSecureTextFieldSubrole {
                return .success(.secure)
            }
        case .failure(.unsupportedTarget):
            break
        case .failure(let failure):
            return .failure(failure)
        }

        let selectedTextSettable = attributeIsSettable(
            kAXSelectedTextAttribute,
            on: element
        )
        let valueSettable = attributeIsSettable(kAXValueAttribute, on: element)
        if selectedTextSettable == true || valueSettable == true {
            return .success(.editable)
        }

        let role = copyStringAttribute(kAXRoleAttribute, from: element)
        let textRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        return .success(textRoles.contains(role ?? "") ? .readOnly : .unsupported)
    }

    func selectedTextRange() -> Result<AXTextRange, DomainFailure> {
        guard let focusedElement else {
            return .failure(.invalidTarget)
        }

        switch copyAttribute(kAXSelectedTextRangeAttribute, from: focusedElement) {
        case .success(let value):
            guard CFGetTypeID(value) == AXValueGetTypeID() else {
                return .failure(.unsupportedTarget)
            }
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var range = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &range) else {
                return .failure(.unsupportedTarget)
            }
            return .success(
                AXTextRange(
                    location: max(0, range.location),
                    length: max(0, range.length)
                )
            )
        case .failure(.unsupportedTarget):
            return .success(AXTextRange(location: 0, length: 0))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure> {
        guard let focusedElement else {
            return .failure(.invalidTarget)
        }
        return copyString(kAXSelectedTextAttribute, from: focusedElement)
    }

    func fullValue() -> Result<String, DomainFailure> {
        guard let focusedElement else {
            return .failure(.invalidTarget)
        }
        return copyString(kAXValueAttribute, from: focusedElement)
    }

    func bounds(for range: AXTextRange) -> Result<CGRect?, DomainFailure> {
        guard let focusedElement else {
            return .failure(.invalidTarget)
        }

        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return .success(nil)
        }

        var rawValue: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &rawValue
        )
        guard error == .success, let rawValue else {
            return isOptionalGeometryError(error)
                ? .success(nil)
                : .failure(map(error))
        }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return .success(nil)
        }

        let axValue = unsafeDowncast(rawValue, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return .success(nil)
        }
        return .success(rect)
    }

    func retainedTargetReference() -> AXTargetReference? {
        guard let focusedElement, let focusedPID else {
            return nil
        }
        return AXTargetReference(
            element: focusedElement,
            window: focusedWindow,
            pid: focusedPID
        )
    }

    private func copyString(
        _ attribute: String,
        from element: AXUIElement
    ) -> Result<String, DomainFailure> {
        switch copyAttribute(attribute, from: element) {
        case .success(let value):
            guard let string = value as? String else {
                return .failure(.unsupportedTarget)
            }
            return .success(string)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func copyStringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        guard case .success(let value) = copyAttribute(attribute, from: element) else {
            return nil
        }
        return value as? String
    }

    private func copyAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> Result<CFTypeRef, DomainFailure> {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue
        )
        guard error == .success, let rawValue else {
            return .failure(map(error))
        }
        return .success(rawValue)
    }

    private func attributeIsSettable(
        _ attribute: String,
        on element: AXUIElement
    ) -> Bool? {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        )
        guard error == .success else {
            return nil
        }
        return settable.boolValue
    }

    private func isOptionalGeometryError(_ error: AXError) -> Bool {
        error == .attributeUnsupported || error == .noValue
    }

    private func map(_ error: AXError) -> DomainFailure {
        switch error {
        case .apiDisabled:
            return .accessibilityPermissionRequired
        case .cannotComplete:
            return .axCannotComplete
        case .invalidUIElement, .invalidUIElementObserver:
            return .invalidTarget
        case .attributeUnsupported, .noValue:
            return .unsupportedTarget
        default:
            return .unknown
        }
    }
}
