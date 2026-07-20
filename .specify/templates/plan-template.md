---
feature: "{{NNN-short-name}}"
stage: plan
status: draft
spec_version: "{{approved spec commit SHA}}"
---

# {{Feature name}} — Technical Plan

## Technical context

Summarize repository facts, platform constraints, approved dependencies, and feasibility findings.

## Constitution Check

Explain how the plan satisfies each relevant constitutional article and identify any required escalation.

## Architecture and component boundaries

- {{Component and responsibility}}

## Interfaces and data flow

Describe inputs, outputs, state transitions, ownership, and any public protocols or schemas.

## Privacy and security

Describe data access, credential use, logging exclusions, secure-input handling, and threat boundaries.

## Failure and recovery

- {{Failure}} → {{observable state and recovery action}}

## Test strategy

- Unit: {{coverage}}
- Integration: {{coverage}}
- Manual: {{compatibility evidence}}

## Rollout and compatibility

Describe migration, feature gating, rollback, and supported environments when applicable.

## Plan Gate record

- Review commit SHA: {{SHA}}
- Reviewer verdict: {{PASS|CHANGES REQUESTED}}
- PR review reference: {{URL or comment ID}}
