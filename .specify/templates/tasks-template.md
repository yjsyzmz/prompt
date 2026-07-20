---
feature: "{{NNN-short-name}}"
stage: tasks
status: draft
plan_version: "{{approved plan commit SHA}}"
---

# {{Feature name}} — Tasks

## Dependency order

Describe the shortest valid execution sequence and identify independent tasks.

## Requirement traceability

| Requirement | Acceptance | Test task | Implementation task |
| --- | --- | --- | --- |
| FR-001 | AC-001 | T-001 | T-002 |

## Tasks

- [ ] **T-001 [Test]** {{Write a failing test or validation harness}} — Covers: FR-001, AC-001
- [ ] **T-002 [Implementation]** {{Implement the minimum behavior}} — Depends on: T-001; Covers: FR-001
- [ ] **T-003 [Verification]** {{Run automated and manual acceptance}} — Depends on: T-002; Covers: AC-001

## Checkpoints

- {{Independently verifiable checkpoint}}

## Tasks Gate record

- Review commit SHA: {{SHA}}
- Reviewer verdict: {{PASS|CHANGES REQUESTED}}
- PR review reference: {{URL or comment ID}}
