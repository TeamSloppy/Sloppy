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

Do not create workflows outside this skill.
