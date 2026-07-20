# Solar × Fable operating guide

## User responsibilities

The user does not perform day-to-day technical review. The user only:

1. Wakes the next Agent with the Session Start message from `AGENTS.md`.
2. Resolves decisions explicitly escalated as `NEEDS DECISION`.
3. Performs `Squash and merge` after the current SHA has Reviewer `PASS`, all required checks are green, and no blocking findings remain.

## Agent alignment

Both Agents reconstruct state from Git and GitHub instead of previous chat context. The active PR must identify the feature, stage, Owner, Reviewer, and head SHA. Every new session posts an Alignment ACK before acting.

## Review freeze

After the Owner posts HANDOFF, the branch is frozen. If a new commit is required, the Owner cancels the review and posts a new handoff. Reviews always name the exact SHA they cover.

## Final merge checklist

- Reviewer verdict is `PASS` for the current head SHA.
- No unresolved `BLOCKER` or `MUST` finding exists.
- `sdd-check`, `secret-scan`, `build`, and `unit-tests` are green.
- The PR is free of merge conflicts.
- The user selects `Squash and merge` and deletes the remote branch.

## Initial sequence

1. Merge the collaboration bootstrap PR.
2. Configure `main` protection with no bypass actors.
3. Solar creates `feature/001-system-interaction-foundation` and owns its four gates.
4. Fable reviews feature `001` from the exact handoff SHA.
5. Roles rotate for `002-model-connection`.
