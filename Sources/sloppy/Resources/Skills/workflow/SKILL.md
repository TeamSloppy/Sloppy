---
name: workflow
description: Create visual workflow plans for project work, with typed graph nodes, links to agent execution, and Dashboard URLs.
userInvocable: true
allowedTools:
  - project.current
  - project.task_list
  - project.task_get
  - project.workflow
---

# Workflow

## Contract-first authoring

Before constructing any payload, read [API reference](references/api.md). Obtain the
current exposed tool schema and compare the canonical DTO/parser; provider all-fields
schemas do not make empty strings valid optional conditions. Prefer omission/null for
unused edge conditions; never condition:"" or conditionKey:"". If the transport cannot
omit them, use supported HTTP definition API with objects and explicit required fields.

Choose [sequential](examples/sequential.json) for trigger → agent → End, or
[approval + Parallel/Join](examples/approval-parallel.json) for gated independent work.
These complete tool JSON payloads run through the actual parser/validator in tests.
Resolve real project/agent/task IDs and read full task descriptions before adapting.
Config taskId does not bind a step; the run task is pinned at Start. Put real child IDs
in prompts and fetch their full requirements. Check reachability and End paths yourself;
the draft validator deliberately allows incomplete plans. Never start to test saving.

After errors follow reference recovery: distinguish parse/graph/policy failures, fix
only proven causes, list/read before retrying uncertain saves. Do not repeat task or
workflow side effects. Report source test results separately from installed runtime.
Run `python3 scripts/check-workflow-contract.py` in the checkout to detect source drift.
Installed skills outside the checkout need explicit synchronization after delivery;
editing this canonical resource does not hot-update an already running agent.


Use this skill when the user explicitly asks for a workflow, visual plan, workflow-mode execution, or when the task benefits from a visible step graph.

When active:
- inspect project and task context first
- create a draft workflow proposal before substantial work
- model work as lanes, nodes, and edges
- use `project.workflow` for workflow state; do not write workflow files directly
- configure `agent_step` with agentId and an explicit new/shared/compact session policy; inspect persisted typed session bindings
- update workflow state from runtime events and tool results, not model-output text
- after creating or completing a workflow, provide the Dashboard workflow URL

Executable `agent_step` nodes require `config.agentId` and a nonempty `config.prompt`.
They start a fresh, project/task-scoped session and wait for its typed terminal outcome.
Use `{{input.<key>}}` and `{{nodes.<id>.output.text}}` to pass input and previous answers.
Optional `model`, `reasoningEffort`, and `mode` use the ordinary agent-session settings.
The step output includes `agentId`, `sessionId`, `text`, and `agentOutcome`.
Inspect that session for details on errors or input waits; neither counts as success.
Input waits keep the workflow pending. Answer the original session's input request to
continue; Human Input blocks require a nonempty response in the action comment.
Each run pins its graph version, original input, prior outputs and step/session IDs.
Approval decisions and user answers resume that run, including after a server restart.
Interrupted agent steps retain their session history. An external operation without a
confirmed persisted result blocks for reconciliation instead of being repeated.
Agent steps default to `config.sessionMode: "new"`. Set `sessionMode: "shared"` with
`sessionSourceNodeId` referencing an earlier completed agent step in the same run, using
the same agent. This continues that session's history while preserving separate outputs.
The source must be completed/idle and keep the same project/task scope; unavailable
sources fail instead of silently creating new context. Do not use raw config.sessionId.
Persisted message boundaries prevent an older answer from completing the new step.
Use `sessionMode: "compact"` with `sessionSourceNodeId` for a summarized handoff into a
fresh target session (the target agent may differ). The summary, source boundary,
summary session and working session are checkpointed; restart does not resummarize a
completed handoff. Summary input is bounded to the latest 64000 characters through the
selected completed source turn, and the summary must contain at most 32000 characters.
Optional `config.outputSchema` validates the complete step output. It supports type,
properties, required, items, enum, minLength and boolean additionalProperties; unsupported
keywords fail validation. `config.outputFormat: "json"` makes an agent return strict JSON
stored in `output.result`, with the original answer retained in `output.text`.
Use edge `condition: {"path":"result.verdict","equals":"approved"}` for typed branches,
or legacy conditionKey, never both. Missing fields, references and ambiguous routes fail.
Use at most one fallback edge per node. Full-value tool templates retain JSON types.
The Dashboard starts and resumes runs in the background and refreshes their status.
API clients can use `background: true`. Parallel, child-workflow and environment setup
runs default to background execution; explicit `background: false` waits for execution.

Parallel nodes require `config.joinNodeId` and 2–16 distinct unconditional outgoing branches.
Join nodes wait for all branches and expose their final outputs under `branches.<startNodeId>`.
Branches must be disjoint until the Join; nested groups are unsupported. Each branch has
a durable cursor and attempt history. Completed work is skipped after restart; uncertain
external effects block for reconciliation. Human and native input waits resume their own
branch independently. Join `config.strategy` defaults to `all`; `first_completed` selects
a successful winner and cancels the remaining branches. Legacy condition/Merge nodes
can serve as the explicitly owned join, with the same strategies.

Starting with taskId snapshots the real project task; templates can use `{{task.title}}`,
`{{task.description}}` and `{{input.task.id}}`. Never substitute invented task fields.
Use the `environment` JSON argument on `project.workflow start`: mode `project`,
`task_worktree`, `existing_worktree` (path), or `new_worktree` (optional baseRef).
Optional setupCommand runs once before graph execution. Base revision, provider,
working directory and branch are pinned. Changed live task/project settings do not
redirect a paused run. Task-owned workflows exclude competing root runs and ordinary
task pickup until completion/cancellation (blocked runs retain ownership).
Use an idempotencyKey UUID to deduplicate starting the same request. New worktrees are
retained for inspection; workflows do not merge or remove them automatically.

Executable blocks: trigger, Project Task snapshot, agent/AI transform, Parallel/Join,
Bash, JavaScript/Python, registered tools, HTTP, human approval/input, typed conditions,
Expression, bounded Loop, Merge, Notify/Channel, task status updates, sub-workflow and End.
Expression supports field paths, exists(path), strict JSON equality/comparison, boolean
operators and numeric arithmetic. A Loop expression can use one-based iteration;
maxIterations is 1–24 (default 10), with the durable per-node attempt cap still 25.
Notify requires a project channelId and message and succeeds only on a delivery receipt.
Sub-workflow requires workflowId, waits for its real terminal state, rejects recursion,
and pins an idempotent child-run binding. Inspect and repair a failed child before
retrying the parent; retry retains the original child and its completed effects.
Every successful path must reach an End; missing/ambiguous transitions fail explicitly.

Use the run retry API/Dashboard reconciliation controls only after inspecting external
effects. Retry records evidence and a fresh attempt without repeating completed earlier
steps. Verified-result continuation validates the pinned output contract and actual
native/child completion. Interrupted setup needs explicit reconciliation. Missing
checkpoints never silently downgrade a pinned environment to legacy execution.
The cancel API/Dashboard stops owned sessions/processes/children and retires pending
questions; it does not roll back completed effects. Run history retains decisions.

Do not create workflows outside this skill.
