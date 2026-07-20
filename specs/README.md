# Feature specifications

Each product feature lives in `specs/NNN-short-name/` and advances through one Draft PR.

Minimum artifacts by stage:

| Stage | Required artifacts |
| --- | --- |
| Spec | `spec.md` |
| Plan | `spec.md`, `plan.md`, `research.md` |
| Tasks | `spec.md`, `plan.md`, `research.md`, `tasks.md` |
| Implementation | All Tasks-stage artifacts plus code and verification evidence in the PR |

Copy templates from `.specify/templates/`. Replace every placeholder before requesting review. The feature Owner updates the `stage` field only after the previous gate has a Reviewer `PASS` on the exact commit SHA.
