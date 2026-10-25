# Workflow execution and contracts

Runs use their pinned definition, including contracts and session policy. Existing graphs
default to text answers and a new agent session for each step.

## Outputs

An optional `config.outputSchema` validates the complete persisted step output before a
transition is selected, including continuation after human or agent input. Failed validation
retains the output for inspection and fails that attempt without starting downstream work.

Supported schema keywords: `type`, `properties`, `required`, `items`, `enum`, `minLength`,
`additionalProperties` (boolean), and `description`. Types are object, array, string,
number, integer, boolean and null. The root describes an object; nesting is limited to 16.
Unknown keywords are rejected. This is a deliberately bounded contract format, not a full
JSON Schema implementation. Required fields may be null only when their declared type allows null.

Agent steps with `config.outputFormat: "json"` must return exactly one JSON value. Markdown
fences or prose fail the step. The parsed value is stored in `output.result`; `output.text`
retains the original answer. User-controlled JSON cannot overwrite `agentId`, `sessionId`,
execution status or other envelope fields. The ordinary typed terminal outcome is still required.

```json
{
  "agentId": "developer",
  "prompt": "Return a verdict and a short explanation.",
  "outputFormat": "json",
  "outputSchema": {
    "type": "object",
    "required": ["result"],
    "properties": {
      "result": {
        "type": "object",
        "required": ["verdict"],
        "properties": {"verdict": {"type": "string", "enum": ["approved", "rejected"]}}
      }
    }
  }
}
```

Tool contracts describe their actual output fields, such as `stdout` or `exitCode`.
JSON mode is an agent setting; it does not imply parsing shell stdout.

## Transitions and references

An edge may use a legacy `conditionKey` or a typed condition, never both:

```json
{"id":"reviewed","sourceNodeId":"review","targetNodeId":"done","condition":{"path":"result.verdict","equals":"approved"}}
```

The path is relative to that node's output. Comparison preserves JSON types, so `false`,
`0`, and `"0"` differ. Missing typed fields and multiple matching edges fail the attempt.
An edge without either condition is the fallback; there can be only one per ordinary node.
Multiple edges launch concurrent work only from an explicit Parallel block. Drafts may remain unfinished, but a running
path must reach an explicit End node. Invalid updates leave the saved version unchanged.

Templates use `{{input.ticket}}` and `{{nodes.review.output.result.verdict}}`. Unknown nodes,
malformed placeholders and unavailable runtime fields are errors. Unexecuted branches
do not supply an output. Array elements can be addressed by index, such as `result.items.0`.
A whole-value template in tool arguments retains its JSON type; interpolation inside
text produces text. The `project.workflow` tool accepts `condition` as an object or JSON
object string, preserving boolean, null and numeric values.

The Dashboard exposes output format/schema and transition-rule controls. Invalid JSON
in these controls prevents Save and Run until corrected.

## Agent sessions

`config.sessionMode` chooses `new` (the default), `shared`, or `compact`. New sessions receive the
step's workflow input and outputs; sharing retains the native conversation and tool history.
Shared mode also requires `config.sessionSourceNodeId`, identifying an earlier agent step
in this run using the same agent. For example, a revision step can select Implementation
while an independent reviewer keeps a new session.

```json
{"agentId":"developer","prompt":"Apply the review comments.","sessionMode":"shared","sessionSourceNodeId":"implementation"}
```

The source must have executed successfully; its session must be completed and idle, with
the same project/task scope. A skipped source, another agent, or unavailable history fails
explicitly. It never falls back to a fresh session. Runs do not share sessions with one another.
Raw `config.sessionId` remains unsuitable as an execution policy; use the source-step field.

The binding and `sessionAfterEventId` boundary are checkpointed before posting the new
request. A shared step reads only its own later events for output and terminal status,
including after input waits or server restart. Earlier messages remain available to the
model through the native session. A missing boundary fails rather than reading unrelated
history. Old checkpoints without a boundary retain their original fresh-session behavior.
Keep the output envelope open to additional execution metadata; close a `result` subtree
with `additionalProperties: false` when a strict payload is needed.

The Dashboard's custom session-source dropdown lists preceding steps using the selected
agent. Inside a parallel group, a shared-session source must belong to the same branch.
Compact creates a bounded summary of the selected completed source turn, then a fresh
working session with the target agent. The target can differ from the source. Both
sessions, the summary and phase are persisted before posting work; restart resumes the
saved phase. History is bounded to the latest 64000 characters through the selected
source completion, with a summary limit of 32000 characters. This costs an additional
model turn; it is not a guarantee of lower total token spend.

## Parallel branches and Join

Add a Parallel block (`type: "parallel"`) and a Join block (`type: "join"`). Select the Join
in the Parallel inspector (`config.joinNodeId`). Connect the Parallel to 2–16 distinct
branch starts with unconditional edges. Every branch must reach that Join. Each Join has
exactly one owner. Branches cannot overlap, have incoming edges from outside their group,
terminate before Join, or contain nested Parallel/Join groups. Legacy condition/Merge blocks can serve as an explicitly owned Join. They do not
start parallel execution by themselves. Join `config.strategy` is `all` (the default)
or `first_completed`. The latter selects one successful winner, cancels the rest and
passes only the winner's branch outputs; failures before a winner still stop the group.

Each branch receives the pre-fork input and upstream outputs. It can read its own earlier
steps. Sibling outputs become available downstream only after every branch succeeds.
The Parallel output exposes final branch results under `branches.<branchStartId>`;
after Join, references such as `{{nodes.review.output.text}}` and
`{{nodes.qa.output.stdout}}` address individual successful steps.

Approval, Human Input and native agent questions can pause separate branches. Answering
one continues that branch while the others keep running or waiting. Each attempt, action,
native session binding and pinned graph is saved in the parent's atomic checkpoint.
Server restart skips completed branches and restores the original pending questions;
an external operation with no durably recorded result requires reconciliation before retry.

A failed branch cancels the remaining work and closes outstanding workflow/native input
waits. Join and downstream steps do not execute. Completed side effects are not rolled back.
Explicit cancellation of a native question cancels the group. Parallel API runs default to
background execution; `background: false` explicitly waits for full completion. Background
receipts expose current branch node IDs, and the existing run API supplies step history.

All branches share the run's pinned execution directory. This can be a new worktree that
isolates the entire run from the source checkout; per-branch worktree isolation is not
implemented. Shell node cwd overrides must stay within that pinned directory.

## Task and execution environment

Start a run with a real project `taskId` to snapshot its fields. Use `{{task.title}}`,
`{{task.description}}`, or `{{input.task.id}}`. Project Task outputs that snapshot;
Update Task writes the bound live task's status. Renaming the task during an approval
wait does not change the input already assigned to the run. A second root workflow
cannot claim an active task; ordinary task pickup also respects the durable ownership.
Cancelling the task cancels its owning workflow. Child workflows share the parent's
snapshot and execution directory.

The create-run API and Dashboard launch form accept:

```json
{
  "taskId": "PROJECT-1",
  "startedBy": "owner",
  "background": true,
  "input": {"ticket": "WF-42"},
  "environment": {
    "mode": "new_worktree",
    "baseRef": "HEAD",
    "setupCommand": "npm ci"
  }
}
```

Modes: `project`, `task_worktree`, `existing_worktree` with an absolute `path`, and
`new_worktree` with `baseRef` (default HEAD). Git branch/tag/revision references are
resolved to a commit when the run is created. `origin/HEAD` uses local remote-HEAD
metadata; no implicit fetch occurs. Existing Git worktrees must belong to the source
repository. The resolved provider, canonical directory, branch and revision are saved
in the atomic run checkpoint and returned as `run.environment`.

The trigger's optional `config.executionEnvironment` supplies defaults for callers that
omit environment. The Dashboard always lets the user review the choice before Start.
`task`, `environment`, cwd and internal ancestry are server-owned input fields. Tool
calls cannot redirect runtime.exec outside the pinned directory. Native session tool
roots are restored from the workflow checkpoint even when answering after restart.

Setup is checkpointed before execution. A confirmed successful setup is not repeated;
an interrupted setup is blocked for explicit reconciliation. Setup prepares the
environment; use a Bash/Code workflow node when its output must feed later steps.
New managed worktrees are retained with their changes, without automatic merge/removal.
The API supports an optional `idempotencyKey` UUID: repeating the same start request
returns the pinned run; using the same key for different input fails.

## Expression, Loop, Merge and notifications

Expression/Loop are condition nodes with `config.blockKind` and `config.expression`.
They evaluate a deterministic bounded language, without JavaScript evaluation or model
prose classification. Supported operators: `!`, `&&`, `||`, strict typed `==`/`!=`
(and `===`/`!==` aliases), `<`, `<=`, `>`, `>=`, and numeric `+`, `-`, `*`, `/`.
Use parentheses, field paths and `exists(path)`. Missing evaluated fields, mismatched
types, division by zero and non-boolean results fail explicitly. Subtraction should be
spaced when a path could also contain a hyphen. Strings use single/double quotes.

The boolean is written to output.result, with `true`/`false` route flags. For example,
`iteration <= 2` with `maxIterations: 2` runs a body twice, then follows the false edge.
A Loop permits 1–24 true iterations (default 10); a still-true condition beyond that
limit fails. The existing 25-attempt per-node cap remains durable across input waits,
restarts and explicit retries. Merge is an owned join as described above.

Notify/Channel requires `config.channelId` from the project and `config.message`.
A registered channel plugin must confirm delivery; a missing/failed plugin fails the
step. Unknown interrupted delivery is not sent again automatically. JavaScript and
Python are the supported Code runtimes; unsupported saved language values fail.

## Child workflows, cancellation and reconciliation

Sub-workflow is a tool_check with blockKind sub_workflow and workflowId. Optional
config.input supplies a JSON object whose templates are resolved from parent input.
The parent waits in waiting_for_workflow, exposing childRunId/childStatus and collected
child node outputs on success. It never treats a queued receipt as completion. Child
bindings are idempotent, recursion is rejected and nesting is limited to eight workflows.
A repaired child's parent can be retried using the same child ID and completed effects.
The Activity panel links child runs and displays native questions through the shared
question UI; ordinary manual approvals remain independently answerable.

`POST /v1/projects/:projectId/workflow-runs/:runId/cancel` takes `{ "userId": "owner" }`.
It fences subsequent journal writes, cancels owned sessions/processes/children, and
retires pending questions. Completed effects are retained. A blocked run can be
cancelled to release task ownership.

`POST /v1/projects/:projectId/workflow-runs/:runId/retry` requires stepId, decision,
evidence and userId. Decision retry starts a fresh attempt with the saved incoming
input and retains completed earlier steps. A parallel parent retry restarts only its
unfinished branches. Accept_result also requires output JSON, validates the pinned
contract, and for native/child steps requires actual recorded completion. Native session
IDs, message boundaries and compact-phase metadata remain server-owned during reconciliation. Child outputs
are reconstructed from the completed child's checkpoint. An uncertain shell result
must explicitly report exitCode zero. Reconciliation records retain the previous step,
operator, evidence and decision. Old attempts remain visible in history.

A missing directory/provider or changed managed branch blocks continuation instead of
falling back to another environment. Restore the binding and reconcile __environment
before continuing. A missing authoritative checkpoint cannot safely reconstruct a pinned
worktree or parallel group from the query index. Legacy histories remain readable;
completed effects are never rolled back by these controls.
