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

Use this skill when the user explicitly asks for a workflow, visual plan, workflow-mode execution, or when the task benefits from a visible step graph.

When active:
- inspect project and task context first
- create a draft workflow proposal before substantial work
- model work as lanes, nodes, and edges
- use `project.workflow` for workflow state; do not write workflow files directly
- link `agent_step` nodes to agent/session/delegated-task IDs through typed metadata
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
Sharing one session across different graph nodes is not supported yet.
Optional `config.outputSchema` validates the complete step output. It supports type,
properties, required, items, enum, minLength and boolean additionalProperties; unsupported
keywords fail validation. `config.outputFormat: "json"` makes an agent return strict JSON
stored in `output.result`, with the original answer retained in `output.text`.
Use edge `condition: {"path":"result.verdict","equals":"approved"}` for typed branches,
or legacy conditionKey, never both. Missing fields, references and ambiguous routes fail.
Use at most one fallback edge per node. Full-value tool templates retain JSON types.
The Dashboard starts and resumes runs in the background and refreshes their status.
API clients can opt in with `background: true`; existing calls remain synchronous.

Currently executable blocks: manual trigger, agent/AI transform, Bash, JavaScript/Python,
registered tools, HTTP, human approval/input decisions, typed field conditions, task status
updates, and explicit End nodes. Expression evaluation, Loop/Merge blocks, Notify and Project
Task execution and sub-workflow completion tracking are not implemented and fail explicitly. Every successful path must reach
an End node; a missing matching transition fails the run. Multiple edges do not imply parallelism.

Do not create workflows outside this skill.
