import CoreGraphics
import Foundation

/// T-029 synthetic AX host.
///
/// An in-process stand-in for an external application's focused text element.
/// It implements both gateway-facing protocols so `AccessibilityGateway` can
/// run its full capture and authoritative write/recovery pipeline against
/// deterministic fixtures without touching any real application.
///
/// Synthetic semantics (shared with the T-021 authoritative fake): the
/// selection start stays stable across writes, while the selected range length
/// follows the current selected content and the selected content itself is
/// modeled by `segment`. All content carries the
/// `SYNTHETIC-001` marker and never comes from a real application.
final class SyntheticAXTextHost: @unchecked Sendable {
    static let syntheticMarker = "SYNTHETIC-001"

    let pid: Int32

    private let lock = NSLock()
    private let selectionLocation: Int
    private var reportedSelectionLocation: Int
    private var reportedSelectionLength: Int
    private let anchorBounds: CGRect?

    private var prefix: String
    private var segment: String
    private var suffix: String
    private var capability: AXFocusedElementCapability
    private var secureInputActive: Bool
    private var applicationRunning = true
    private var frontmostPID: Int32
    private var windowGeneration = 0
    private var elementGeneration = 0
    private var capturedWindowGeneration = -1
    private var capturedElementGeneration = -1
    private var remainingForcedSetterFailures = 0
    private var remainingForcedContentReadFailures = 0
    private var setterSilentlyDropsWrites = false
    private var replacementAttributeBlocked = false

    private var contentReads = 0
    private var setterAttempts = 0
    private var selectedSetterAttempts = 0
    private var wholeFieldSetterAttempts = 0

    private init(
        prefix: String,
        segment: String,
        suffix: String,
        selectionLength: Int,
        capability: AXFocusedElementCapability,
        secureInputActive: Bool,
        anchorBounds: CGRect?,
        pid: Int32
    ) {
        self.prefix = prefix
        self.segment = segment
        self.suffix = suffix
        selectionLocation = prefix.utf16.count
        reportedSelectionLocation = selectionLocation
        reportedSelectionLength = selectionLength
        self.capability = capability
        self.secureInputActive = secureInputActive
        self.anchorBounds = anchorBounds
        self.pid = pid
        frontmostPID = pid
    }

    /// Test hook for oversized fixtures: replaces the whole field content while
    /// keeping the host in whole-field (no selection) mode.
    func replaceFullTextForTesting(_ text: String) {
        prefix = ""
        segment = text
        suffix = ""
        reportedSelectionLength = 0
    }

    // MARK: - Fixtures

    static func selectionFixture(pid: Int32 = 4_001) -> SyntheticAXTextHost {
        let segment = "\(syntheticMarker) 选中的合成文字"
        return SyntheticAXTextHost(
            prefix: "\(syntheticMarker) 前缀 ",
            segment: segment,
            suffix: " \(syntheticMarker) 后缀",
            selectionLength: segment.count,
            capability: .editable,
            secureInputActive: false,
            anchorBounds: CGRect(x: 120, y: 240, width: 200, height: 20),
            pid: pid
        )
    }

    static func wholeFieldFixture(pid: Int32 = 4_002) -> SyntheticAXTextHost {
        SyntheticAXTextHost(
            prefix: "",
            segment: "\(syntheticMarker) 整段合成文字",
            suffix: "",
            selectionLength: 0,
            capability: .editable,
            secureInputActive: false,
            anchorBounds: nil,
            pid: pid
        )
    }

    static func emptyFixture(pid: Int32 = 4_003) -> SyntheticAXTextHost {
        SyntheticAXTextHost(
            prefix: "",
            segment: "",
            suffix: "",
            selectionLength: 0,
            capability: .editable,
            secureInputActive: false,
            anchorBounds: nil,
            pid: pid
        )
    }

    static func readOnlyFixture(pid: Int32 = 4_004) -> SyntheticAXTextHost {
        SyntheticAXTextHost(
            prefix: "",
            segment: "\(syntheticMarker) 只读合成文字",
            suffix: "",
            selectionLength: 0,
            capability: .readOnly,
            secureInputActive: false,
            anchorBounds: nil,
            pid: pid
        )
    }

    static func secureInputFixture(pid: Int32 = 4_005) -> SyntheticAXTextHost {
        SyntheticAXTextHost(
            prefix: "",
            segment: "\(syntheticMarker) 安全输入占位",
            suffix: "",
            selectionLength: 0,
            capability: .secure,
            secureInputActive: true,
            anchorBounds: nil,
            pid: pid
        )
    }

    // MARK: - Inspection

    var fullText: String {
        withLock { prefix + segment + suffix }
    }

    var selectedSegment: String {
        withLock { segment }
    }

    var reportedSelectedRange: AXTextRange {
        withLock {
            AXTextRange(location: reportedSelectionLocation, length: reportedSelectionLength)
        }
    }

    var contentReadCount: Int {
        withLock { contentReads }
    }

    var setterAttemptCount: Int {
        withLock { setterAttempts }
    }

    var selectedSetterAttemptCount: Int {
        withLock { selectedSetterAttempts }
    }

    var wholeFieldSetterAttemptCount: Int {
        withLock { wholeFieldSetterAttempts }
    }

    // MARK: - Controlled external events

    func switchWindow() {
        withLock { windowGeneration += 1 }
    }

    func invalidateElement() {
        withLock { elementGeneration += 1 }
    }

    func failNextSetterAttempts(_ count: Int) {
        withLock { remainingForcedSetterFailures = count }
    }

    /// MUST 1: the setter reports success but the value never lands, which is how
    /// a silently dropped write reaches the readback stage.
    func acceptSetterWithoutApplying() {
        withLock { setterSilentlyDropsWrites = true }
    }

    /// MUST 1: makes the element read-only after capture so that the capability
    /// stage can be reached on the replacement path.
    func makeReadOnly() {
        withLock { capability = .readOnly }
    }

    /// MUST 1: keeps the element editable but refuses the replacement attribute,
    /// which is a different rejection than a read-only element.
    func blockReplacementAttribute() {
        withLock { replacementAttributeBlocked = true }
    }

    func activateGlobalSecureInput() {
        withLock { secureInputActive = true }
    }

    /// MUST 1: an unreadable target must be distinguishable from a changed one.
    func failNextContentReads(_ count: Int) {
        withLock { remainingForcedContentReadFailures = count }
    }

    func editSegmentExternally(_ newSegment: String) {
        withLock { segment = newSegment }
    }

    func collapseSelectionAfterWrite() {
        withLock {
            reportedSelectionLocation = selectionLocation + segment.utf16.count
            reportedSelectionLength = 0
        }
    }

    func terminateApplication() {
        withLock { applicationRunning = false }
    }

    func moveFocusToDifferentApplication() {
        withLock { frontmostPID = pid &+ 1 }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Capture-side protocol

extension SyntheticAXTextHost: AXCaptureReading {
    /// Hands the gateway a placeholder AX reference so that handle retention and
    /// release are observable in tests. The element is never written to; all
    /// authoritative access goes through this host.
    func retainedTargetReference() -> AXTargetReference? {
        .placeholder(pid: pid)
    }

    func focusedElementCapability() -> Result<AXFocusedElementCapability, DomainFailure> {
        withLock {
            capturedWindowGeneration = windowGeneration
            capturedElementGeneration = elementGeneration
            return .success(capability)
        }
    }

    func selectedTextRange() -> Result<AXTextRange, DomainFailure> {
        withLock {
            .success(
                AXTextRange(
                    location: reportedSelectionLocation,
                    length: reportedSelectionLength
                )
            )
        }
    }

    func selectedText(in range: AXTextRange) -> Result<String, DomainFailure> {
        withLock {
            guard range.location == selectionLocation else {
                return .failure(.sourceChanged)
            }
            guard consumeForcedContentReadFailureIfNeeded() else {
                return .failure(.axCannotComplete)
            }
            contentReads += 1
            return .success(reportedSelectionLength == 0 ? "" : segment)
        }
    }

    func fullValue() -> Result<String, DomainFailure> {
        withLock {
            guard consumeForcedContentReadFailureIfNeeded() else {
                return .failure(.axCannotComplete)
            }
            contentReads += 1
            return .success(prefix + segment + suffix)
        }
    }

    func bounds(for range: AXTextRange) -> Result<CGRect?, DomainFailure> {
        withLock { .success(anchorBounds) }
    }
}

// MARK: - Authoritative-side protocol

extension SyntheticAXTextHost: AXAuthoritativeTargetAccessing {
    func isTargetApplicationRunning(expectedPID: Int32) -> Bool {
        withLock { applicationRunning && expectedPID == pid }
    }

    func currentExternalApplicationPID() -> Int32? {
        withLock { frontmostPID }
    }

    func windowIdentityMatches(targetHandle: TargetHandle) -> Bool {
        withLock { windowGeneration == capturedWindowGeneration }
    }

    func elementIdentityMatches(targetHandle: TargetHandle) -> Bool {
        withLock { elementGeneration == capturedElementGeneration }
    }

    func currentElementCapability() -> AXFocusedElementCapability {
        withLock { capability }
    }

    func isGlobalSecureInputActive() -> Bool {
        withLock { secureInputActive }
    }

    func isReplacementAttributeSettable(for mode: CaptureMode) -> Bool {
        withLock { capability == .editable && !replacementAttributeBlocked }
    }

    func setSelectedText(_ value: String) -> Bool {
        withLock {
            setterAttempts += 1
            selectedSetterAttempts += 1
            guard consumeForcedFailureIfNeeded() else {
                return false
            }
            guard capability == .editable else {
                return false
            }
            guard !setterSilentlyDropsWrites else {
                return true
            }
            segment = value
            reportedSelectionLength = value.utf16.count
            return true
        }
    }

    func setWholeValue(_ value: String) -> Bool {
        withLock {
            setterAttempts += 1
            wholeFieldSetterAttempts += 1
            guard consumeForcedFailureIfNeeded() else {
                return false
            }
            guard capability == .editable else {
                return false
            }
            guard !setterSilentlyDropsWrites else {
                return true
            }
            prefix = ""
            suffix = ""
            segment = value
            return true
        }
    }

    private func consumeForcedContentReadFailureIfNeeded() -> Bool {
        guard remainingForcedContentReadFailures > 0 else {
            return true
        }
        remainingForcedContentReadFailures -= 1
        return false
    }

    private func consumeForcedFailureIfNeeded() -> Bool {
        guard remainingForcedSetterFailures > 0 else {
            return true
        }
        remainingForcedSetterFailures -= 1
        return false
    }
}
