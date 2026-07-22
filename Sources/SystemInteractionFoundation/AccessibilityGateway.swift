import AppKit
import ApplicationServices
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

extension AXCaptureReading {
    func retainedTargetReference() -> AXTargetReference? {
        nil
    }
}

final class AXTargetReference: @unchecked Sendable {
    fileprivate let element: AXUIElement

    fileprivate init(element: AXUIElement) {
        self.element = element
    }
}

actor AccessibilityGateway {
    private let captureReader: any AXCaptureReading
    private let sourceTextFactory: any AXSourceTextCreating
    private var targetReferences: [TargetHandle: AXTargetReference] = [:]

    init(
        captureReader: any AXCaptureReading,
        sourceTextFactory: any AXSourceTextCreating = DefaultAXSourceTextFactory()
    ) {
        self.captureReader = captureReader
        self.sourceTextFactory = sourceTextFactory
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
}

final class SystemAXCaptureReader: AXCaptureReading, @unchecked Sendable {
    private var focusedElement: AXUIElement?

    func focusedElementCapability() -> Result<AXFocusedElementCapability, DomainFailure> {
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
        focusedElement.map(AXTargetReference.init(element:))
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
