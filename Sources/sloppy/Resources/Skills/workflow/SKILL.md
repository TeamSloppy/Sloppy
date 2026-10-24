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
Existing-session continuation is not supported yet.

Currently executable blocks: manual trigger, agent/AI transform, Bash, JavaScript/Python,
registered tools, HTTP, human approval/input decisions, typed field conditions, task status
updates, and explicit End nodes. Expression evaluation, Loop/Merge blocks, Notify and Project
Task execution and sub-workflow completion tracking are not implemented and fail explicitly. Every successful path must reach
an End node; a missing matching transition fails the run. Multiple edges do not imply parallelism.

Do not create workflows outside this skill.
