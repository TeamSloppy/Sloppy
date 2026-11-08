# Runner commands

The public [validation guide](../../docs/guides/contributor-validation.md) owns setup,
command examples and status meanings. Read it when using the runner for the first time.

Use `sloppy-feature-flow` for features/improvements, `sloppy-tdd` for implementation and
`sloppy-review` in a separate subagent context for final review. Scoped maintenance can use
`init --kind maintenance`; this does not waive required product-design approval for a
change that is actually a feature or contract-changing improvement.

Task paths are exact repository-relative files. `scope` adds new owned files; pre-existing
unrelated edits remain outside the task. A newly changed file outside scope blocks transition.
Final reports and reviews fingerprint the full worktree. Re-running validation after an edit assembles
a fresh report and reuses successful built-in checks with unchanged dependency/tool/log fingerprints.
Unknown dependencies and Node commands rerun. This does not transfer ownership of unrelated edits.

TDD cycles are retained by ID, including failed Green/Refactor attempts. `tdd --phase red --cycle ID
--behavior "..."` starts a named cycle; Green/Refactor can select it with `--cycle ID`. Without an ID,
Red creates one and other phases use the latest cycle. `tdd-history --task TASK` prints the history.
The legacy `tdd` field remains the selected cycle for existing callers. Refactor is optional when
there was no refactoring change. Earlier logs remain part of the reviewed evidence.

`approve-design --source` stores the actual approval reference, not an invented approval.
The script cannot authenticate chat authors. Likewise `record-review` checks structural
independence and final fingerprints; the real separate context must exist.

Commands passed to TDD/runtime/platform/dependency options are JSON argv arrays, never
shell strings. Prefer `--command-file` for TDD to avoid shell quoting errors. Do not embed
credentials in command arguments, environment overrides or documentation examples.
