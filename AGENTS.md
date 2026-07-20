# Solar × Fable Collaboration Protocol

This file applies to the entire repository. It is the primary operating contract for every agent session.

## 1. Source of truth

Read authoritative context in this order before acting:

1. `AGENTS.md`
2. `.specify/memory/constitution.md`
3. `docs/superpowers/specs/2026-07-17--design.md`
4. The active feature's `spec.md`, `plan.md`, `research.md`, and `tasks.md`
5. The active pull request description, handoff comments, review comments, and checks
6. The current commit diff

Chat history is never a durable source of truth. Any decision that changes scope, behavior, architecture, testing, or risk acceptance must be written back to an approved artifact or the pull request.

## 2. Agents, roles, and worktrees

- Solar and Fable share one GitHub account but must identify themselves in every handoff, review, and stage-changing comment.
- Every feature has exactly one `Owner` and one `Reviewer`.
- The Owner is the only agent allowed to modify the feature branch.
- The Reviewer must not push to the Owner branch. Reproduction work belongs in a detached checkout or a temporary `review/<feature>-<agent>` branch.
- Roles rotate by product feature. Solar owns feature `001`; Fable owns feature `002`.
- Only one product feature may be active until the user explicitly changes the WIP limit.
- Local worktrees are `.worktrees/solar` and `.worktrees/fable` and must never be committed.

## 3. Session Start

Every agent must complete this sequence before changing files or reviewing:

1. Confirm the repository and worktree path.
2. Run `git status --short --branch`. Stop if unexpected changes exist.
3. If `origin` exists, run `git fetch origin --prune`.
4. Read the sources of truth listed in section 1.
5. Discover the one active feature PR and record its head SHA, stage, Owner, and Reviewer.
6. Reviewer sessions must inspect the exact handoff SHA, not an unspecified moving branch.
7. Publish an `ALIGNMENT ACK` in the PR. During local bootstrap, return it to the user for posting.

No development or review may start before the acknowledgement is complete.

```text
ALIGNMENT ACK
Acting-Agent: Solar | Fable
Repository:
HEAD SHA:
Main SHA:
Active PR:
Feature:
Current Stage:
Role: Owner | Reviewer
Authoritative files read:
Current approved decisions:
Actions I must not perform:
Required checks:
My exact next action:
Unresolved questions:
```

## 4. SDD lifecycle

One feature uses one branch and one evolving Draft PR. Its stages are strictly ordered:

1. `Spec Gate`: approve problem, scope, requirements, and acceptance scenarios.
2. `Plan Gate`: approve architecture, interfaces, data flow, risk handling, and test strategy.
3. `Tasks Gate`: approve requirement coverage, dependency order, task size, and test-first execution.
4. `Implementation Gate`: approve code, automated checks, manual evidence, privacy, and known limitations.

The Owner may not start the next stage without a Reviewer `PASS` for the current stage. A material change to an approved artifact reopens that gate and all downstream gates.

## 5. Branch, commit, and PR rules

- Product branch: `feature/NNN-short-name`.
- Process branch: `chore/NNN-short-name`.
- Never commit directly to `main` after repository bootstrap.
- Never force-push shared branches.
- Keep the PR as Draft until the Implementation Gate is ready for final review.
- Every stage-changing commit message must be concise and include these trailers:

```text
Acting-Agent: Solar | Fable
SDD-Stage: Spec | Plan | Tasks | Implementation
Feature: NNN
```

- Do not commit secrets, user content, API keys, signing assets, generated credentials, local environment files, or agent worktrees.

## 6. Handoff contract

Before requesting review, the Owner must commit and push all intended work, verify a clean worktree, run the relevant checks, and freeze the branch.

```text
HANDOFF
Acting-Agent:
Feature / Stage:
Owner / Reviewer:
Review commit SHA:
Changed artifacts:
Requirements covered:
Decisions made:
Validation and results:
Known risks:
Open questions:
Exact review request:
```

Any push after `HANDOFF` invalidates the review request. The Owner must issue a new handoff with the new SHA.

## 7. Review contract

```text
REVIEW
Acting-Agent:
Reviewed commit SHA:
Gate:
Verdict: PASS | CHANGES REQUESTED
Findings:
Independent validation:
Residual risks:
Next required action:
```

Finding levels:

- `BLOCKER`: security, data loss, or fundamental specification conflict.
- `MUST`: violation of an approved requirement, plan, or acceptance criterion.
- `SHOULD`: material quality improvement that may be deferred only with a recorded reason.
- `QUESTION`: clarification request; non-blocking unless promoted with evidence.
- `NIT`: minor, non-blocking suggestion.

The Owner replies to each finding with `FIXED`, `DECLINED`, or `NEEDS DECISION` and supporting evidence. Only the Reviewer closes findings. `BLOCKER` and `MUST` findings prevent `PASS`.

## 8. Merge and dispute rules

- The user is the only person who performs the final GitHub merge.
- Merge only when the Reviewer passed the current head SHA, required checks are green, and no blocking findings remain.
- Use `Squash and merge`, then delete the remote feature branch.
- Resolve disagreements using, in order: approved product design, constitution, current feature spec, reproducible tests, and documented evidence.
- If evidence cannot resolve the disagreement, record `NEEDS DECISION` and ask the user. Do not continue by assumption.

## 9. Recovery rules

- Only pushed commits are recoverable state. Uncommitted work is not a handoff.
- A replacement Reviewer performs a full review of the current SHA and does not inherit verbal approval.
- Merge-conflict resolution belongs to the Owner and requires checks to be rerun.
- If conflict resolution changes an approved specification or plan, reopen the corresponding gate.
- A flaky check may be rerun once. A repeated failure must be investigated and cannot be bypassed.

## 10. Fable wake-up message

The user may start a Fable session with only this message:

```text
项目路径：
/Users/daidong/Documents/prompt/.worktrees/fable

请执行 AGENTS.md 中的 Session Start 和 Alignment ACK 流程。
自行查找当前打开的功能 PR。
在完成信息对齐、确认当前 commit SHA 和你的角色前，不要修改文件、分支或 PR。
```
