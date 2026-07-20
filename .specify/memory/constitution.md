# Prompt Workspace Constitution

**Version:** 1.0.0
**Ratified:** 2026-07-20
**Status:** Active

## Article I — Specifications are authoritative

No product behavior may be implemented without an approved feature specification and acceptance scenarios. Code, tests, and documentation must trace back to approved requirements. When behavior changes, update and reapprove the specification before changing implementation.

## Article II — Preserve user control and text

The application must never alter source text before explicit user confirmation. Every cross-application write path must preserve a recoverable original and provide a clipboard fallback. Password fields and secure input areas must never be read or processed.

## Article III — Privacy and credential safety

API keys belong in macOS Keychain and must not appear in source, ordinary configuration, logs, analytics, fixtures, or screenshots. User input, generated output, prompt bodies, variable values, and clipboard contents must not enter telemetry. New data collection requires an approved specification and explicit user consent.

## Article IV — Native macOS reliability first

The first release optimizes for reliable macOS system integration. Native platform behavior, accessibility permissions, focus handling, and fallback paths take precedence over premature cross-platform abstraction.

## Article V — Testable requirements and evidence

Every functional requirement must have at least one acceptance scenario. Implementation tasks must identify their requirement coverage and put relevant tests before production code. System-integration behavior that cannot be automated requires a recorded manual compatibility result.

## Article VI — Independent review

The feature Owner may not approve their own gate. Review must target an exact commit SHA and include independent validation. Material changes invalidate prior approval. Blocking findings cannot be waived without a documented user decision.

## Article VII — Minimal scope

Implement only the current approved feature. Future cloud AI, accounts, sync, community, Windows, and local models remain out of scope until separately specified. Avoid abstractions that exist only for unapproved future work.

## Article VIII — Failure must be understandable and recoverable

Permission denial, unavailable inputs, invalid credentials, network failures, model errors, lost focus, and insertion failures must produce understandable user states with a safe next action. Silent data loss and silent failure are prohibited.

## Governance

- This constitution applies to every specification, plan, task list, review, and implementation.
- A proposed amendment requires a dedicated process PR, Solar and Fable review, explicit user approval, and a version increment.
- Reviewers must include a Constitution Check in every Plan Gate.
- If a lower-level artifact conflicts with this constitution, the lower-level artifact must be corrected before work continues.
