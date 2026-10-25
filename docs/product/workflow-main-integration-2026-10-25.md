# Workflow integration into main — 2026-10-25

The user explicitly authorized integrating all merged PR changes into `main`, resolving conflicts along the way. This single integration branch consolidates the existing workflow stack; it does not split the implementation into additional feature PRs.

## Audit

The audit inspected every merged PR returned by GitHub (56 records), its merge commit, its source parent and current `origin/main` ancestry.

| PRs | Before integration | Integration action |
|---|---|---|
| 60 | Already in main at `3542fd26` | Preserve real-agent execution |
| 61–66 | Merged into preceding feature branches, absent from main | Include snapshots, resume/recovery, graph/output contracts and shared sessions |
| 67 | Already in main at `0f429907` | Preserve TUI model loading, background Undo and newer per-turn behavior |
| 68–70 | Merged through the feature stack, ending at `17988635` | Include parallel execution/input, task/worktree binding, remaining blocks, recovery controls and editor |

Every implementation commit from PRs 61–66 is already reachable from `17988635`; those PRs contain no additional non-merge commits outside that tip and main. The merged source of PRs 68–70 is also reachable from this tip. Merging the final tip once therefore includes the complete stack without replaying individual patches.

Other apparently absent historical merge SHAs do not represent lost changes:

- PRs 43 and 55–58 have source commits already reachable from main.
- PRs 2–15 have corresponding merge commits in main with identical Git trees despite different commit SHAs.
- PR 1's source commit is already in main.
- All remaining merged PR commits were already ancestors of main.

## Conflict resolution

The sole Git conflict is modify/delete on `Sources/Protocols/APIModels.swift`. Main had split this monolith into domain files. Apply exactly the workflow stack's model changes to `Sources/Protocols/API/WorkflowAPIModels.swift` and retain deletion of the old monolith. Preserve every other main domain model, the SQLite domain-file split and versioned migrations.

Git merged the two workflow session-reconciliation hooks into `CoreService+Sessions.swift` alongside main's per-turn session changes. TUI sources and tests are inherited unchanged from main, including PR 67. The eight unrelated dirty files in the original checkout are left untouched; integration and verification use a separate worktree.

The integration diff against main contains 5,827 reviewable code/test lines before this audit document (6,429 textual lines including existing docs, plus one existing screenshot). The user explicitly requested a single consolidated integration; this diff represents previously reviewed feature PRs rather than a new decomposition.

## Upstream checks

At audit time PR 70's release builds on Linux/macOS, SloppyNode on macOS/Windows, Dashboard build, Dashboard Happy Path and license compliance passed. Its earlier Windows runtime-regression job was cancelled; the repeated Windows job passed. Swift test jobs are disabled in the existing CI configuration, so their skipped results do not establish test coverage.

## Integration verification

The integration PR records results from the consolidated source: workflow/session/input/heartbeat tests, TUI and SQLite migration checks, Dashboard tests/typecheck/build, and release builds for both executables. The existing disabled Swift CI test jobs are not counted as coverage. Production deployment is separate from merging source into main.
