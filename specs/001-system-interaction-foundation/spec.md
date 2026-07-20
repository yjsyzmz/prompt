---
feature: "001-system-interaction-foundation"
stage: spec
status: in_review
owner: "Solar"
reviewer: "Fable"
product_design: "docs/superpowers/specs/2026-07-17--design.md"
---

# System interaction foundation — Specification

## Problem and outcome

The product depends on reading and replacing text across unrelated macOS applications without losing the user's work. That system interaction is the highest-risk dependency for every later prompt-library and AI-optimization feature, but it has not yet been proven as one complete user flow.

This feature delivers a model-free capability probe. While the application is already running, a user invokes one temporary global shortcut, captures the current selection or editable field, reviews a clearly marked deterministic test result in a floating preview, and explicitly chooses whether to replace the source text. Permission denial, unsupported targets, changed focus, and failed insertion remain understandable and recoverable through explicit clipboard actions. The outcome is compatibility evidence for representative native, browser, and Electron inputs without committing the product to final names, layout, model behavior, or technical architecture.

## Goals

- Prove an end-to-end shortcut-to-preview-to-confirmation flow in representative macOS text inputs.
- Demonstrate that source text is never modified before explicit confirmation.
- Demonstrate selection-first capture and whole-field capture when no non-empty selection exists.
- Demonstrate safe target revalidation, replacement, in-session source recovery, and explicit clipboard fallback.
- Make missing permissions, unsafe inputs, empty inputs, unsupported targets, shortcut conflicts, and failed writes understandable and recoverable.
- Record reproducible compatibility results for TextEdit, Chrome with ChatGPT, and VS Code.

## Out of scope

- AI generation, model requests, streaming output, API keys, model configuration, or provider tutorials.
- Prompt-library, optimization-rule, template, search, collection, or persistence behavior.
- Real-time mode, background text monitoring, or automatic transformation.
- Accounts, synchronization, community, analytics, telemetry, or content history.
- A final product name, feature name, visual system, floating-panel layout, or permanent shortcut combination.
- User-configurable shortcut recording or a complete settings experience.
- A final onboarding, installer, distribution, signing, or update flow.
- Windows support or identical control behavior in every third-party application.
- Technical architecture, framework selection, interface design, task decomposition, or application implementation.

## User stories

### US-001 — Invoke without leaving the current task

As a frequent Prompt user, I want to invoke the tool with one global shortcut while editing in another application, so that I can test the system interaction without switching workflows.

### US-002 — Preview before changing text

As a user protecting unfinished work, I want to see the captured source and deterministic test result before any write occurs, so that I remain in control of the original text.

### US-003 — Replace only the intended target

As a user working across applications and windows, I want replacement to occur only when the original target is still valid, so that a stale action cannot modify unrelated text.

### US-004 — Complete the flow when direct access is restricted

As a user of an application with limited system text access, I want clear clipboard-based recovery actions, so that I can still complete the test flow without losing the result or source.

### US-005 — Recover the original after replacement

As a user who confirmed a test replacement, I want an immediate way to restore the captured original, so that validation cannot leave my text irreversibly changed.

### US-006 — Understand permission and safety boundaries

As a user without Accessibility permission or with a secure input focused, I want an understandable refusal and safe next action, so that the tool neither fails silently nor reads protected content.

## Functional requirements

- **FR-001 — Global trigger:** While the application is already running, the system shall register one documented temporary global shortcut. A registration failure or detected conflict shall produce an understandable state instead of silent non-operation. The exact combination is not a permanent product decision.
- **FR-002 — Permission gate:** Before reading or writing another application's text, the system shall verify the required macOS Accessibility permission. When permission is absent, it shall not read or modify target content and shall offer an explanation, an action that opens the relevant System Settings location, and a recheck action. It may also offer a user-initiated clipboard path.
- **FR-003 — Secure-input refusal:** When the focused element is reported as a password field or secure input area, the system shall not read, transform, display, log, copy, or modify its content. It shall show only a content-free safety explanation.
- **FR-004 — Selection-first capture:** When the focused editable element contains a non-empty selection, the system shall capture only that selection. Otherwise, it shall attempt to capture the complete value of the focused editable element.
- **FR-005 — Empty and unsupported targets:** When no non-empty text can be captured, or the focused element cannot be established as an editable target, the system shall not create a result and shall provide an understandable next action.
- **FR-006 — Deterministic validation result:** For a successful capture, the system shall produce the exact local validation result `【系统交互验证】`, followed by one newline and the captured text. The result shall be visibly identified as validation-only behavior and shall require no model or network request.
- **FR-007 — Safe floating preview:** The system shall display the validation result without modifying source text. It shall prefer an anchor near the caret, selection, or input element when bounds are available; otherwise it shall use a safe position within the target window or active display. The preview shall remain fully visible on the active screen.
- **FR-008 — Explicit preview actions:** The preview shall offer Confirm replacement, Copy result, and Cancel. Confirm shall be the only action that attempts direct source replacement. Copy shall be the only normal action that writes the result to the clipboard. Cancel shall close the interaction without changing source text or clipboard contents.
- **FR-009 — Target revalidation:** Immediately before any direct write, the system shall revalidate the originating application, window, editable element, and relevant source range or value. Interacting with the tool's own preview shall not itself invalidate the target. An external target or focus change shall disable direct replacement while keeping Copy result and Cancel available.
- **FR-010 — Replacement and fallback:** After a valid confirmation, the system shall replace only the originally captured selection or whole-field value. If replacement cannot be completed safely, it shall leave source text unchanged, retain the result in the current preview, explain the failure, and offer an explicit Copy result action.
- **FR-011 — Single active session:** The system shall maintain at most one interaction session and one floating preview. Repeated shortcut triggers shall not stack windows or allow an older session to write over a newer target.
- **FR-012 — Recoverable original:** After a successful replacement, the system shall keep the captured original in memory and expose a short-lived Restore original action for the current session. Restore shall revalidate the target before writing. If restoration cannot be completed safely, the system shall retain the original and offer an explicit Copy original action. Starting a new session or dismissing the success state ends application-managed recovery; the target application's system Undo remains an additional compatibility observation.
- **FR-013 — Ephemeral content lifecycle:** Real user text, validation results derived from real user text, and recoverable originals shall exist only for the current in-memory session. They shall not be written to disk, ordinary configuration, logs, analytics, screenshots, or test artifacts, and shall be cleared when the session ends. Automated validation may use committed, non-sensitive synthetic text that contains no credential-like value and is clearly identified as test data.

## Non-functional requirements

- **NFR-001 — Responsiveness:** With the application already running, a visible preview shell or explicit permission, conflict, empty-input, or unsupported-target state shall appear within 300 milliseconds of the shortcut in at least 9 of 10 consecutive attempts in each required full-loop environment. The validation record shall identify the Mac, macOS version, application version, and measurement method.
- **NFR-002 — No pre-confirmation mutation:** Across all automated and manual acceptance runs, the number of source-text mutations before Confirm replacement shall be zero.
- **NFR-003 — Compatibility floor:** TextEdit and Chrome with ChatGPT shall complete the full capture, preview, confirm, replace, and recovery flow. VS Code shall complete at least the explicit clipboard fallback flow; direct capture and replacement, when available, shall be recorded separately rather than assumed.
- **NFR-004 — Input robustness:** Chinese, English, mixed-language, empty, multiline, long, and special-character inputs shall not cause a crash, silent failure, unintended truncation, or unrelated text modification. The long-text test size shall be recorded with the result rather than treated as an unlimited guarantee.
- **NFR-005 — Display safety:** On single- and multi-display configurations, including an input near a visible screen edge, the preview shall remain fully visible on one active display.
- **NFR-006 — Privacy:** Validation shall produce no persisted real user content and no user-content-bearing logs, screenshots, artifacts, or telemetry. Clipboard contents shall not be read or changed unless the user explicitly selects a clipboard fallback or copy action. Automated evidence shall use only non-sensitive synthetic text.
- **NFR-007 — Understandable recovery:** Every refusal or failure state shall name the failed capability in user language and present at least one safe next action. Raw platform error codes alone are insufficient.

## Acceptance scenarios

### AC-001 — Register and invoke the temporary shortcut

- **Given** the application is already running and the temporary shortcut is available
- **When** the user presses the shortcut from TextEdit or Chrome
- **Then** the system begins one interaction session and displays a preview shell or explicit state within the NFR-001 threshold

### AC-002 — Explain a shortcut conflict

- **Given** the temporary shortcut cannot be registered
- **When** the application initializes the global trigger
- **Then** the user sees that the shortcut is unavailable and receives a safe next action without the feature appearing silently functional

### AC-003 — Recover from missing Accessibility permission

- **Given** Accessibility permission is not granted
- **When** the user presses the shortcut
- **Then** no target text is read or modified, and the user can open the relevant System Settings location, recheck permission, or choose a user-initiated clipboard path

### AC-004 — Refuse secure input

- **Given** a password field or secure input area is focused
- **When** the user presses the shortcut
- **Then** no content is captured, transformed, displayed, logged, copied, or modified, and a content-free safety explanation appears

### AC-005 — Replace only a TextEdit selection

- **Given** TextEdit contains surrounding text and one non-empty selection
- **When** the user invokes the feature, reviews the validation result, and confirms replacement
- **Then** the preview initially leaves all source text unchanged, confirmation replaces only the selected range, and surrounding text remains byte-for-byte unchanged

### AC-006 — Replace a Chrome ChatGPT input without a selection

- **Given** the ChatGPT input in Chrome is focused, contains non-empty text, and has no non-empty selection
- **When** the user invokes the feature and confirms replacement
- **Then** the deterministic result represents the complete input value and only that input value is replaced

### AC-007 — Explain empty or unsupported input

- **Given** the focused target is empty or cannot be established as editable
- **When** the user invokes the feature
- **Then** no empty result is generated, no source or clipboard mutation occurs, and an understandable next action appears

### AC-008 — Cancel without side effects

- **Given** a valid preview is visible and the clipboard has a known pre-test value
- **When** the user selects Cancel
- **Then** the preview closes, source text is unchanged, and the clipboard retains the pre-test value

### AC-009 — Block a stale target write

- **Given** a valid preview exists for one target
- **When** the user externally changes application, window, or editable input before confirmation
- **Then** direct replacement is disabled, the original target is unchanged, and Copy result and Cancel remain available

### AC-010 — Complete the VS Code fallback flow

- **Given** VS Code does not permit reliable direct capture or replacement in the tested configuration
- **When** the user invokes the feature or a confirmed write fails
- **Then** the system explains the restricted capability, retains any available result, and allows the user to explicitly copy the result for manual paste without changing unrelated text

### AC-011 — Prevent stacked or stale sessions

- **Given** one interaction session is active
- **When** the user presses the global shortcut again
- **Then** no second floating window is stacked and no older session can later write to its previous target

### AC-012 — Restore the original after successful replacement

- **Given** a confirmed replacement succeeded and the current session remains active
- **When** the user selects Restore original while the same target remains valid
- **Then** the captured original replaces only the validation result and no unrelated text changes

### AC-013 — Preserve recovery when direct restoration is unsafe

- **Given** a confirmed replacement succeeded but the original target later becomes invalid
- **When** the user selects Restore original
- **Then** no direct write occurs, the original remains available in memory, and the user can explicitly copy it

### AC-014 — Clear private session content

- **Given** a session has captured source text and produced a result
- **When** the session is cancelled, dismissed after success, replaced by a new session, or otherwise ended normally
- **Then** the application clears the source, result, and recovery copy from session memory and no real user content appears in files, configuration, logs, analytics, screenshots, or test artifacts

### AC-015 — Keep the preview visible across display positions

- **Given** an editable target is near any screen edge or on a secondary display
- **When** a preview or explicit state appears
- **Then** the entire preview is visible on one active display, using a safe fallback position when accurate input bounds are unavailable

### AC-016 — Handle representative text shapes without data loss

- **Given** Chinese, English, mixed-language, multiline, long, or special-character source text
- **When** the user captures, previews, confirms, cancels, copies, or restores according to the relevant flow
- **Then** the application does not crash, silently truncate content, or modify unrelated text, and the validation record identifies any application-specific limitation

### AC-017 — Record target-application Undo behavior

- **Given** a direct replacement succeeded in a required compatibility application
- **When** the application-managed recovery state is dismissed and the user invokes the target application's standard Undo
- **Then** the observed restoration behavior is recorded as compatibility evidence without being treated as a substitute for FR-012

## Requirement traceability

| Requirement | Acceptance evidence |
| --- | --- |
| FR-001 | AC-001, AC-002 |
| FR-002 | AC-003 |
| FR-003 | AC-004 |
| FR-004 | AC-005, AC-006 |
| FR-005 | AC-007 |
| FR-006 | AC-005, AC-006, AC-016 |
| FR-007 | AC-005, AC-006, AC-015 |
| FR-008 | AC-005, AC-006, AC-008, AC-009 |
| FR-009 | AC-009, AC-012, AC-013 |
| FR-010 | AC-005, AC-006, AC-010 |
| FR-011 | AC-011 |
| FR-012 | AC-012, AC-013, AC-017 |
| FR-013 | AC-014 |
| NFR-001 | AC-001 |
| NFR-002 | AC-003 through AC-016 |
| NFR-003 | AC-005, AC-006, AC-010 |
| NFR-004 | AC-007, AC-016 |
| NFR-005 | AC-015 |
| NFR-006 | AC-003, AC-004, AC-008, AC-014 |
| NFR-007 | AC-002, AC-003, AC-004, AC-007, AC-009, AC-010, AC-013 |

## Edge cases and failure behavior

- A zero-length selection is treated as no selection; whole-field capture is attempted.
- Whitespace-only text is valid non-empty text and is preserved exactly after the validation marker.
- If source content changes after capture but before confirmation, the target is stale and direct replacement is blocked.
- If input bounds are unavailable or invalid, the preview uses a safe target-window or active-display position instead of failing the entire flow.
- If the preview itself receives interaction, that internal interaction does not count as an external target change; the originating target still must pass revalidation before writing.
- If direct capture fails before a result exists, the user may explicitly choose a clipboard-input path after manually copying source text. The application does not inspect the clipboard automatically.
- If direct replacement or restoration fails, the system preserves the applicable result or original in the current session and offers explicit copying; it never clears or overwrites the target as a fallback.
- If the application exits unexpectedly after a successful replacement, application-managed in-memory recovery is unavailable. The compatibility record must include the target application's standard Undo result, while FR-012 remains the normal in-session recovery guarantee.
- If a new shortcut trigger supersedes an existing session, the existing preview and its write authority end before the new capture begins.
- If text length or application behavior exceeds the validated envelope, the system reports the limitation rather than claiming universal compatibility.

## Dependencies and assumptions

- The feature targets macOS and assumes the application is already running; cold-launch and login-item behavior are outside this Spec Gate.
- The user actively invokes every capture. No background monitoring or real-time processing is permitted.
- macOS Accessibility authorization is an explicit user-controlled dependency for direct cross-application reading and writing.
- The exact minimum supported macOS version and implementation mechanism are Plan Gate decisions, but every validation result must record its OS and application versions.
- TextEdit represents native macOS text controls, Chrome with ChatGPT represents browser text input, and VS Code represents an Electron application with potentially restricted direct access.
- Compatibility means either the documented full loop or the documented clipboard fallback; it does not imply identical control across all applications.
- The deterministic validation marker and temporary shortcut are disposable validation behavior and do not establish final product copy or interaction design.
- Automated tests and recorded screenshots use only clearly identified, non-sensitive synthetic text and never use copied real-world user content or credential-like values.
- Fable independently reviews the exact Spec commit SHA before any planning begins.

## Spec Gate record

- User design approval: confirmed in the product-design dialogue before repository write
- Review commit SHA: pending Owner HANDOFF
- Reviewer verdict: awaiting Fable review
- PR review reference: PR #2
- Downstream authorization: Plan Gate, Tasks Gate, and implementation are not authorized
