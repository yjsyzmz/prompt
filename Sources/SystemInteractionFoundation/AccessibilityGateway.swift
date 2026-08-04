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

/// Carries the raw AX element out of the actor solely so that the main-actor
/// observer scheduler can subscribe to it. It exposes no text.
final class AXMonitoringTarget: @unchecked Sendable {
    let element: AXUIElement
    let pid: Int32

    init(element: AXUIElement, pid: Int32) {
        self.element = element
        self.pid = pid
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

    /// Placeholder reference for synthetic hosts, so that handle retention and
    /// release are observable without a real focused element.
    static func placeholder(pid: Int32) -> AXTargetReference {
        AXTargetReference(
            element: AXUIElementCreateApplication(pid),
            window: nil,
            pid: pid
        )
    }
}

actor AccessibilityGateway: AXMonitorEventReceiving {
    private let captureReader: any AXCaptureReading
    private let sourceTextFactory: any AXSourceTextCreating
    private let authoritativeTarget: (any AXAuthoritativeTargetAccessing)?
    /// MUST 1: content-free stage classification for the replacement path.
    private let diagnostics: (any ReplacementDiagnosticsRecording)?
    /// T-061: the readback budget is measured on a monotonic clock, and the wait
    /// between readbacks is injected so both bounds are assertable.
    private let clock: any MonotonicClockReading
    private let sleeper: any MonotonicSleeping
    private let readbackBudget: ReadbackBudget
    private var readbackAttempts = 0
    private var targetReferences: [TargetHandle: AXTargetReference] = [:]
    private var activeMonitorEnvelope: AXMonitorCallbackEnvelope?
    private var monitorInvalidationSink: (any AXMonitorInvalidationReceiving)?

    init(
        captureReader: any AXCaptureReading,
        sourceTextFactory: any AXSourceTextCreating = DefaultAXSourceTextFactory(),
        authoritativeTarget: (any AXAuthoritativeTargetAccessing)? = nil,
        diagnostics: (any ReplacementDiagnosticsRecording)? = nil,
        clock: any MonotonicClockReading = SystemMonotonicClock(),
        sleeper: any MonotonicSleeping = SystemMonotonicSleeper(),
        readbackBudget: ReadbackBudget = .default
    ) {
        self.captureReader = captureReader
        self.sourceTextFactory = sourceTextFactory
        self.authoritativeTarget = authoritativeTarget
        self.diagnostics = diagnostics
        self.clock = clock
        self.sleeper = sleeper
        self.readbackBudget = readbackBudget
    }

    /// T-061: how many readbacks the actor has performed. Lets a test prove that
    /// an aborted loop really left its remaining budget unspent.
    func readbackAttemptCount() -> Int {
        readbackAttempts
    }

    /// MUST 1: lets the assembly tests confirm that the production wiring really
    /// supplies a stage recorder.
    func diagnosticsIsAttached() -> Bool {
        diagnostics != nil
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

    func activateMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle,
        invalidationSink: any AXMonitorInvalidationReceiving
    ) {
        activeMonitorEnvelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
        monitorInvalidationSink = invalidationSink
    }

    func deactivateMonitoring() {
        activeMonitorEnvelope = nil
        monitorInvalidationSink = nil
    }

    func deactivateMonitoring(for sessionID: InteractionSessionID) {
        guard activeMonitorEnvelope?.sessionID == sessionID else {
            return
        }
        deactivateMonitoring()
    }

    /// FR-013 resource accounting: how many raw AX references the actor still
    /// retains. Used to prove stale captures do not leak handles.
    func retainedTargetCount() -> Int {
        targetReferences.count
    }

    func hasActiveMonitoring() -> Bool {
        activeMonitorEnvelope != nil
    }

    /// FR-009: the production monitor needs the captured element to subscribe
    /// element-level notifications. Only the reference and pid leave the actor.
    func monitoringTarget(for targetHandle: TargetHandle) -> AXMonitoringTarget? {
        guard let reference = targetReferences[targetHandle] else {
            return nil
        }
        return AXMonitoringTarget(element: reference.element, pid: reference.pid)
    }

    func authoritativePID(for targetHandle: TargetHandle) -> Int32? {
        if let authoritativeTarget {
            return authoritativeTarget.currentExternalApplicationPID()
        }
        return targetReferences[targetHandle]?.pid
    }

    func releaseTarget(_ targetHandle: TargetHandle) {
        targetReferences[targetHandle] = nil
    }

    func receive(_ envelope: AXMonitorCallbackEnvelope) async {
        guard
            envelope == activeMonitorEnvelope,
            let monitorInvalidationSink
        else {
            return
        }
        await monitorInvalidationSink.disableDirectActions(for: envelope)
    }

    /// T-058: answers *why* the captured target would now be judged stale, using
    /// the same identity checks as the write path's A1–A4.
    ///
    /// It is a pure query: it records nothing, writes nothing, and mutates no
    /// actor state, so calling it cannot change what the monitor path does. It
    /// lives here only because the identity checks are actor-isolated; the
    /// caller decides whether and how to record the answer. The comparison uses
    /// the pid captured with the target, which is the same pid A1 and A2 use.
    func staleTargetAssessment(
        for targetHandle: TargetHandle,
        panelFocus: PanelFocusAuthorization
    ) -> StaleTargetDiagnosticReport {
        guard let pid = targetReferences[targetHandle]?.pid else {
            return StaleTargetDiagnosticReport(reason: .identityUnknown)
        }
        guard targetApplicationIsRunning(pid: pid) else {
            return StaleTargetDiagnosticReport(reason: .applicationTerminated)
        }
        if case .rejected(let focusedApplicationIsSelf) = frontmostApplicationCheck(
            pid: pid,
            panelFocus: panelFocus
        ) {
            return StaleTargetDiagnosticReport(
                reason: .focusedApplicationChanged,
                focusedApplicationIsSelf: focusedApplicationIsSelf
            )
        }
        guard windowMatches(targetHandle: targetHandle) else {
            return StaleTargetDiagnosticReport(reason: .windowIdentityChanged)
        }
        guard elementMatches(targetHandle: targetHandle) else {
            return StaleTargetDiagnosticReport(reason: .elementIdentityChanged)
        }
        return StaleTargetDiagnosticReport(reason: .identityIntact)
    }

    func replaceAfterAuthoritativeValidation(
        _ snapshot: AXWriteSnapshot,
        panelFocus: PanelFocusAuthorization
    ) -> Result<AXRecoveryContext, DomainFailure> {
        guard snapshot.captureMode != .clipboardInput else {
            diagnostics?.record(
                ReplacementStageReport(
                    stage: .unsupportedMode,
                    failure: .unsupportedTarget
                )
            )
            return .failure(.unsupportedTarget)
        }

        switch validate(
            targetHandle: snapshot.targetHandle,
            pid: snapshot.pid,
            mode: snapshot.captureMode,
            expectedText: snapshot.originalText.value,
            panelFocus: panelFocus
        ) {
        case .success:
            break
        case .failure(let failure):
            // `validate` already recorded the stage that rejected the write.
            return .failure(failure)
        }

        guard setText(
            snapshot.transformedText.value,
            mode: snapshot.captureMode,
            targetHandle: snapshot.targetHandle
        ) else {
            diagnostics?.record(
                ReplacementStageReport(stage: .setter, failure: .writeFailed)
            )
            return .failure(.writeFailed)
        }

        switch confirmWrittenText(
            snapshot.transformedText.value,
            mode: snapshot.captureMode,
            targetHandle: snapshot.targetHandle,
            pid: snapshot.pid
        ) {
        case .confirmed:
            break
        case .unconfirmed:
            // The setter reported success but the value never landed. This is a
            // different failure than a refused setter and must stay separable.
            diagnostics?.record(
                ReplacementStageReport(stage: .readback, failure: .writeFailed)
            )
            return .failure(.writeFailed)
        case .aborted:
            // T-061: the target went away mid-confirmation. Fail closed with the
            // same safe fallback, but keep the two causes distinguishable.
            diagnostics?.record(
                ReplacementStageReport(
                    stage: .readbackAborted,
                    failure: .writeFailed
                )
            )
            return .failure(.writeFailed)
        }

        diagnostics?.record(ReplacementStageReport(stage: .completed))
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

    /// Recovery branches on the capture mode first: whole-field captures use the
    /// W1–W4 algorithm and never touch a selected range, while selected
    /// captures continue into C1–C4 with the R1/R2/R3 classification.
    func restoreAfterAuthoritativeValidation(
        _ recovery: AXRecoveryContext,
        panelFocus: PanelFocusAuthorization
    ) -> Result<Void, DomainFailure> {
        switch recovery.captureMode {
        case .clipboardInput:
            return .failure(.recoveryTargetChanged)
        case .wholeField:
            return restoreWholeField(recovery, panelFocus: panelFocus)
        case .selectedText(let capturedRange):
            return restoreSelected(
                recovery,
                capturedRange: capturedRange,
                panelFocus: panelFocus
            )
        }
    }

    /// A1–A4. The settable check is deliberately absent: it belongs to each
    /// path so that it always targets the attribute that path actually writes.
    private func sharedPrechecks(
        targetHandle: TargetHandle,
        pid: Int32,
        panelFocus: PanelFocusAuthorization
    ) -> Result<Void, DomainFailure> {
        guard targetApplicationIsRunning(pid: pid) else {
            return .failure(.invalidTarget)
        }
        if case .rejected = frontmostApplicationCheck(
            pid: pid,
            panelFocus: panelFocus
        ) {
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
        return .success(())
    }

    /// W1–W4.
    private func restoreWholeField(
        _ recovery: AXRecoveryContext,
        panelFocus: PanelFocusAuthorization
    ) -> Result<Void, DomainFailure> {
        if case .failure(let failure) = sharedPrechecks(
            targetHandle: recovery.targetHandle,
            pid: recovery.pid,
            panelFocus: panelFocus
        ) {
            return .failure(failure)
        }

        // W1: the whole value must still equal the expected transformed text.
        guard case .success(let currentValue) = wholeValue(
            targetHandle: recovery.targetHandle
        ),
            currentValue == recovery.expectedTransformedText.value
        else {
            return .failure(.recoveryTargetChanged)
        }

        // W2: only kAXValueAttribute matters on this path.
        guard replacementAttributeIsSettable(
            mode: .wholeField,
            targetHandle: recovery.targetHandle
        ) else {
            return .failure(.recoveryTargetChanged)
        }

        // W3 and W4: exactly one setter, then bounded readback confirmation.
        guard setText(
            recovery.originalText.value,
            mode: .wholeField,
            targetHandle: recovery.targetHandle
        ), confirmWrittenText(
            recovery.originalText.value,
            mode: .wholeField,
            targetHandle: recovery.targetHandle,
            pid: recovery.pid
        ) == .confirmed else {
            return .failure(.recoveryTargetChanged)
        }
        return .success(())
    }

    private enum SelectedRecoveryRoute {
        /// R1: the selection still covers the written result.
        case selectedSetter
        /// R2: a zero-length caret inside the result range, or a missing
        /// selected-range capability.
        case constrainedFallback
    }

    /// C1–C4 with the R1/R2/R3 classification.
    private func restoreSelected(
        _ recovery: AXRecoveryContext,
        capturedRange: AXTextRange,
        panelFocus: PanelFocusAuthorization
    ) -> Result<Void, DomainFailure> {
        if case .failure(let failure) = sharedPrechecks(
            targetHandle: recovery.targetHandle,
            pid: recovery.pid,
            panelFocus: panelFocus
        ) {
            return .failure(failure)
        }

        // C1: expected result range uses UTF-16 code units.
        let expectedResultRange = AXTextRange(
            location: capturedRange.location,
            length: (recovery.expectedTransformedText.value as NSString).length
        )

        // C2: classify the selected-range read.
        let route: SelectedRecoveryRoute
        switch currentSelectedRange(targetHandle: recovery.targetHandle) {
        case .success(let currentRange):
            if currentRange == expectedResultRange {
                route = .selectedSetter
            } else if currentRange.length == 0,
                      currentRange.location >= expectedResultRange.location,
                      currentRange.location
                        <= expectedResultRange.location + expectedResultRange.length {
                // R2 case 1. The caret's provenance is deliberately not
                // inferred; safety comes from the fallback preconditions.
                route = .constrainedFallback
            } else {
                // Non-zero-length mismatch, or a caret outside the result
                // range: both are excluded.
                return .failure(.recoveryTargetChanged)
            }
        case .failure(.unsupportedTarget):
            // R2 case 2: the range attribute is unsupported or absent.
            route = .constrainedFallback
        case .failure(let failure):
            // R3: invalid element, permission, secure input, timeout and
            // cannotComplete must surface as themselves with zero setters.
            return .failure(failure)
        }

        switch route {
        case .selectedSetter:
            return restoreViaSelectedSetter(
                recovery,
                expectedResultRange: expectedResultRange
            )
        case .constrainedFallback:
            return restoreViaSelectedRangeFallback(
                recovery,
                expectedResultRange: expectedResultRange
            )
        }
    }

    /// R1: content check, path-scoped settable check, one selected setter.
    private func restoreViaSelectedSetter(
        _ recovery: AXRecoveryContext,
        expectedResultRange: AXTextRange
    ) -> Result<Void, DomainFailure> {
        guard case .success(let currentText) = selectedText(
            in: expectedResultRange,
            targetHandle: recovery.targetHandle
        ), currentText == recovery.expectedTransformedText.value else {
            return .failure(.recoveryTargetChanged)
        }

        guard replacementAttributeIsSettable(
            mode: recovery.captureMode,
            targetHandle: recovery.targetHandle
        ) else {
            return .failure(.recoveryTargetChanged)
        }

        guard setText(
            recovery.originalText.value,
            mode: recovery.captureMode,
            targetHandle: recovery.targetHandle
        ), confirmWrittenText(
            recovery.originalText.value,
            mode: recovery.captureMode,
            targetHandle: recovery.targetHandle,
            pid: recovery.pid
        ) == .confirmed else {
            return .failure(.recoveryTargetChanged)
        }
        return .success(())
    }

    /// The selected-range recovery fallback and its six preconditions. Any
    /// failure is fail-closed; the selected setter is never used here and a
    /// failed write is never retried.
    private func restoreViaSelectedRangeFallback(
        _ recovery: AXRecoveryContext,
        expectedResultRange: AXTextRange
    ) -> Result<Void, DomainFailure> {
        // 1: kAXValueAttribute must be settable.
        guard replacementAttributeIsSettable(
            mode: .wholeField,
            targetHandle: recovery.targetHandle
        ) else {
            return .failure(.recoveryTargetChanged)
        }

        // 2: read the base value immediately before the setter; never reuse an
        // earlier read.
        guard case .success(let baseValue) = wholeValue(
            targetHandle: recovery.targetHandle
        ) else {
            return .failure(.recoveryTargetChanged)
        }
        let base = baseValue as NSString

        // 3: the expected result range must fall inside the base value.
        guard expectedResultRange.location >= 0,
              expectedResultRange.length >= 0,
              expectedResultRange.location + expectedResultRange.length <= base.length
        else {
            return .failure(.recoveryTargetChanged)
        }
        let resultRange = NSRange(
            location: expectedResultRange.location,
            length: expectedResultRange.length
        )

        // 4: that range must still hold the expected transformed text.
        guard base.substring(with: resultRange)
            == recovery.expectedTransformedText.value
        else {
            return .failure(.recoveryTargetChanged)
        }

        // 5: the written value only replaces that range; every code unit
        // outside it comes from the base value unchanged.
        let restoredValue = base.replacingCharacters(
            in: resultRange,
            with: recovery.originalText.value
        )

        // 6: one setter, then bounded readback confirmation.
        guard setText(
            restoredValue,
            mode: .wholeField,
            targetHandle: recovery.targetHandle
        ), confirmWrittenText(
            restoredValue,
            mode: .wholeField,
            targetHandle: recovery.targetHandle,
            pid: recovery.pid
        ) == .confirmed else {
            return .failure(.recoveryTargetChanged)
        }
        return .success(())
    }

    private func validate(
        targetHandle: TargetHandle,
        pid: Int32,
        mode: CaptureMode,
        expectedText: String,
        panelFocus: PanelFocusAuthorization,
    ) -> Result<Void, DomainFailure> {
        func reject(
            _ stage: ReplacementStage,
            _ failure: DomainFailure,
            focusedApplicationIsSelf: Bool? = nil
        ) -> Result<Void, DomainFailure> {
            diagnostics?.record(
                ReplacementStageReport(
                    stage: stage,
                    failure: failure,
                    focusedApplicationIsSelf: focusedApplicationIsSelf
                )
            )
            return .failure(failure)
        }

        guard targetApplicationIsRunning(pid: pid) else {
            return reject(.applicationRunning, .invalidTarget)
        }
        if case .rejected(let focusedApplicationIsSelf) = frontmostApplicationCheck(
            pid: pid,
            panelFocus: panelFocus
        ) {
            return reject(
                .frontmostApplication,
                .invalidTarget,
                focusedApplicationIsSelf: focusedApplicationIsSelf
            )
        }
        guard windowMatches(targetHandle: targetHandle) else {
            return reject(.windowIdentity, .invalidTarget)
        }
        guard elementMatches(targetHandle: targetHandle) else {
            return reject(.elementIdentity, .invalidTarget)
        }

        switch elementCapability(targetHandle: targetHandle) {
        case .editable:
            break
        case .secure:
            return reject(.elementCapability, .secureInputActive)
        case .readOnly:
            return reject(.elementCapability, .attributeNotSettable)
        case .unsupported:
            return reject(.elementCapability, .unsupportedTarget)
        }

        guard !globalSecureInputIsActive() else {
            return reject(.globalSecureInput, .secureInputActive)
        }

        switch currentText(
            mode: mode,
            targetHandle: targetHandle,
            expectedText: expectedText
        ) {
        case .success(let currentText):
            guard currentText == expectedText else {
                return reject(.contentComparison, .sourceChanged)
            }
        case .failure(let failure):
            return reject(.contentRead, failure)
        }

        guard replacementAttributeIsSettable(
            mode: mode,
            targetHandle: targetHandle
        ) else {
            return reject(.attributeSettable, .attributeNotSettable)
        }
        return .success(())
    }

    /// Replacement-path content check (B1). Recovery has its own algorithm and
    /// does not use this helper.
    private func currentText(
        mode: CaptureMode,
        targetHandle: TargetHandle,
        expectedText: String
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
            return selectedText(in: expectedRange, targetHandle: targetHandle)
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

    /// The outcome of A2, carrying the focus-ownership fact the diagnostics need
    /// so that the frontmost application is read exactly once. Reading it twice
    /// would both cost an extra AX round trip and risk two different answers.
    private enum FrontmostApplicationCheck {
        case acceptable
        case rejected(focusedApplicationIsSelf: Bool)
    }

    /// A2, in one place. Plan `0c9883f` states it as "apart from this tool's own
    /// non-activating panel, no other application has become the user's new
    /// external target".
    ///
    /// The exemption is scoped to the panel the current session is presenting,
    /// not to this process: `panelFocus` is evaluated on `MainActor` at the
    /// instant the action runs and is never cached. Focus on any other window of
    /// this process — a settings window, or the panel already ordered out — is
    /// not an exemption.
    ///
    /// Both the replacement path and the recovery path call this. They used to
    /// carry independent copies of the check, which is how the exemption ended
    /// up applied to one and not the other.
    private func frontmostApplicationCheck(
        pid: Int32,
        panelFocus: PanelFocusAuthorization
    ) -> FrontmostApplicationCheck {
        let focusedPID = currentExternalPID()
        if focusedPID == pid {
            return .acceptable
        }
        let focusedApplicationIsSelf =
            focusedPID == ProcessInfo.processInfo.processIdentifier
        if focusedApplicationIsSelf, panelFocus.currentSessionPanelIsKey {
            return .acceptable
        }
        return .rejected(focusedApplicationIsSelf: focusedApplicationIsSelf)
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
            let currentElement = focusedElement(inApplicationWithPID: target.pid),
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
            let target = targetReferences[targetHandle],
            let currentElement = focusedElement(inApplicationWithPID: target.pid)
        else {
            return false
        }
        return CFEqual(target.element, currentElement)
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

    /// T-061: confirms the write inside a bounded budget.
    ///
    /// Some targets — notably Chromium web content — report a successful
    /// `AXSelectedText`/`AXValue` write without having applied it, because the
    /// renderer applies accessibility writes asynchronously. FR-010 therefore
    /// makes the readback the only success criterion: the setter has already run
    /// exactly once by the time this is called, and nothing here writes — a
    /// retry repeats only the readback.
    ///
    /// The loop ends for one of three reasons — the text was read back
    /// identically, the budget was spent, or the target stopped being valid —
    /// and the caller can tell them apart.
    private func confirmWrittenText(
        _ expectedText: String,
        mode: CaptureMode,
        targetHandle: TargetHandle,
        pid: Int32
    ) -> ReadbackOutcome {
        // (1) The budget is a monotonic deadline. A wall-clock adjustment during
        // the loop cannot shorten or extend it.
        let deadline = clock.now() &+ readbackBudget.totalBudgetNanoseconds
        var backoff = readbackBudget.initialBackoffNanoseconds
        var attempt = 0

        while true {
            // (7) Waiting only makes sense while the target could still both
            // receive the write and report it back.
            guard readbackTargetStillValid(
                targetHandle: targetHandle,
                pid: pid
            ) else {
                return .aborted
            }

            attempt += 1
            readbackAttempts += 1
            if writeReadbackMatches(
                expectedText,
                mode: mode,
                targetHandle: targetHandle
            ) {
                return .confirmed
            }

            guard attempt < readbackBudget.maximumAttempts else {
                return .unconfirmed
            }
            let now = clock.now()
            guard now < deadline else {
                return .unconfirmed
            }
            // (2) Bounded backoff: doubling, capped, and never past the deadline.
            sleeper.sleep(nanoseconds: min(backoff, deadline - now))
            backoff = min(
                backoff &* 2,
                readbackBudget.maximumBackoffNanoseconds
            )
        }
    }

    /// The three observable ways a session or target dies under us: the
    /// application exited, or the window/element identity moved. These are the
    /// same A1／A3／A4 checks the write path already trusts, so a released
    /// capture — which is what ending a session or closing the panel does — also
    /// fails them: with no retained reference there is no window or element left
    /// to match.
    private func readbackTargetStillValid(
        targetHandle: TargetHandle,
        pid: Int32
    ) -> Bool {
        targetApplicationIsRunning(pid: pid)
            && windowMatches(targetHandle: targetHandle)
            && elementMatches(targetHandle: targetHandle)
    }

    /// T-061 (3): the readback comparison unit is the UTF-16 code unit, the same
    /// unit FR-012 already mandates for ranges.
    ///
    /// `String ==` compares canonical forms, so it would accept a target that
    /// silently renormalised the text. That is a different code-unit sequence
    /// than the one we asked for, and confirming it would mean claiming a write
    /// we did not actually make. Prefix or length comparison is excluded for the
    /// same reason.
    private func readbackTextMatches(
        _ candidate: String,
        _ expected: String
    ) -> Bool {
        (candidate as NSString).isEqual(to: expected)
    }

    private func writeReadbackMatches(
        _ expectedText: String,
        mode: CaptureMode,
        targetHandle: TargetHandle
    ) -> Bool {
        switch mode {
        case .selectedText(let expectedRange):
            let expectedLength = (expectedText as NSString).length
            if case .success(let currentRange) = currentSelectedRange(
                targetHandle: targetHandle
            ),
                currentRange == AXTextRange(
                    location: expectedRange.location,
                    length: expectedLength
                ),
                case .success(let selectionValue) = selectedText(
                    in: currentRange,
                    targetHandle: targetHandle
                ),
                readbackTextMatches(selectionValue, expectedText)
            {
                return true
            }
            guard
                case .success(let fullValue) = wholeValue(targetHandle: targetHandle)
            else {
                return false
            }
            let candidateRange = NSRange(
                location: expectedRange.location,
                length: expectedLength
            )
            guard candidateRange.location >= 0,
                NSMaxRange(candidateRange) <= (fullValue as NSString).length,
                readbackTextMatches(
                    (fullValue as NSString).substring(with: candidateRange),
                    expectedText
                )
            else {
                return false
            }
            return true
        case .wholeField:
            guard
                case .success(let fullValue) = wholeValue(targetHandle: targetHandle),
                readbackTextMatches(fullValue, expectedText)
            else {
                return false
            }
            return true
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

    /// Resolves the focused element **inside the target application**.
    ///
    /// The system-wide focused element follows keyboard focus across all
    /// applications, so once the preview panel becomes key it reports this
    /// tool's own control. Asking the target application directly keeps the A3
    /// and A4 identity invariants evaluable while the panel legitimately holds
    /// focus — the same reason Plan `0c9883f` exempts the panel in A2.
    private func focusedElement(inApplicationWithPID pid: Int32) -> AXUIElement? {
        guard
            case .success(let value) = copyAttribute(
                kAXFocusedUIElementAttribute,
                from: AXUIElementCreateApplication(pid)
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
        var elementResult = copyAttribute(
            kAXFocusedUIElementAttribute,
            from: systemWide
        )
        if case .failure = elementResult {
            if let fallback = focusedElementFromFrontmostApplication() {
                elementResult = fallback
            }
        }

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
        let role = copyStringAttribute(kAXRoleAttribute, from: element)
        if selectedTextSettable == true || valueSettable == true {
            return .success(.editable)
        }

        let textRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        return .success(textRoles.contains(role ?? "") ? .readOnly : .unsupported)
    }

    /// Chromium- and Electron-based apps keep their accessibility tree
    /// disabled until an assistive client is detected, so the system-wide
    /// focus query returns no value for them. Enabling the manual
    /// accessibility attributes on the frontmost application and querying
    /// its focused element directly switches the tree on.
    private func focusedElementFromFrontmostApplication()
        -> Result<CFTypeRef, DomainFailure>?
    {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(
            frontmost.processIdentifier
        )
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        for attempt in 0 ..< 6 {
            if attempt > 0 {
                usleep(150_000)
            }
            let result = copyAttribute(
                kAXFocusedUIElementAttribute,
                from: appElement
            )
            if case .success = result {
                return result
            }
        }
        return nil
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
