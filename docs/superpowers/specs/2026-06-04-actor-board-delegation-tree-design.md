# Actor Board Delegation Tree Design

## Status

Proposed design, approved for implementation planning on June 4, 2026.

## Summary

Actor Board should gain a focused Delegation Tree mode for building multi-agent swarm execution trees. The board already stores actors, links, and teams, and the runtime already uses hierarchical one-way task links to start swarms from project tasks. This design makes that existing capability explicit, discoverable, validated, and safe to use.

The first release should not introduce a generic workflow engine. Actor Board remains the place to model actors and relationships. Delegation Tree mode is a constrained execution view over the same board data:

- root agent receives a project task;
- child agent links describe delegation structure;
- each execution link is stored as `communicationType: "task"`, `relationship: "hierarchical"`, and `direction: "one_way"`;
- `SwarmCoordinator` and `CoreService+Swarm` remain the source of truth for execution semantics.

## Goals

- Allow more than one agent to participate in an Actor Board execution structure.
- Make multi-agent delegation trees understandable before a task is launched.
- Use the existing swarm runtime instead of adding a second orchestration engine.
- Keep execution control flow typed. Do not infer task state or branching from model prose.
- Surface graph validation errors in the Dashboard before users assign project tasks.
- Preserve the existing general Actor Board graph for communication, teams, and visual organization.

## Non-Goals

- A generic n8n-style workflow builder.
- Arbitrary conditional branches, payload mapping, tool-call nodes, or human approval nodes.
- Multiple saved delegation-tree templates in the first release.
- Replacing project tasks, project workflows, or the existing swarm implementation.
- Running a delegation tree directly from the board without a project task.

## Current Context

The backend already has the main primitives:

- `ActorBoardSnapshot` contains `nodes`, `links`, and `teams`.
- `ActorNode` can represent humans, agents, and action nodes.
- `ActorLink` contains `direction`, `relationship`, `communicationType`, and sockets.
- `ActorBoardFileStore` synchronizes all configured agents into system `agent:<id>` nodes.
- `SwarmCoordinator.buildHierarchy` turns one-way hierarchical task links into levels.
- `CoreService.startSwarmIfHierarchical` starts a swarm when a ready project task is assigned to an actor with reachable delegation children.

The missing product layer is clarity. Users need a mode that deliberately creates and validates the subset of links that affect swarm execution.

## Product Shape

Actor Board gets a mode switch:

- **Map**: existing free-form actor graph behavior.
- **Delegation Tree**: constrained execution-tree editor for project-task swarms.

Delegation Tree mode shows the same board, but emphasizes only execution-relevant links:

- agent nodes are eligible execution nodes;
- non-agent nodes remain visible but cannot be part of the execution tree;
- one root agent is selected for preview;
- child links are created with task hierarchy defaults;
- invalid links are shown as warnings or blocking errors.

## Delegation Tree Semantics

An execution tree is rooted at one actor id, usually `agent:<agentId>`.

A link participates in the tree only when all are true:

- `communicationType == .task`
- effective relationship is `.hierarchical`
- `direction == .oneWay`
- source and target both resolve to agent actor nodes

Peer links, chat links, discussion links, two-way hierarchical links, missing targets, and non-agent execution targets do not participate in swarm execution.

The tree supports branching. A parent agent may delegate to multiple child agents. Linear pipelines are represented as a tree where each level has one child.

Cycles are blocking errors.

## Dashboard UX

### Mode Switch

Add a compact mode switch near the Actor Board toolbar:

- Map
- Delegation Tree

The switch should not navigate away or duplicate board state. It changes editing affordances, validation, and the inspector.

### Root Selection

Delegation Tree mode needs an explicit root selector. The selector can be:

- the currently selected agent node, when eligible;
- a search dropdown using the existing custom `.actor-team-search` pattern;
- empty when no root is selected.

When a root is selected, the board highlights reachable execution children by depth.

### Agent Management

Users should be able to add multiple agents to the board from Delegation Tree mode:

- select an existing agent;
- create a new agent using the existing agent creation form;
- place the agent near the selected parent or root;
- optionally create a child execution link immediately after adding it.

Existing system agent nodes should remain protected from content edits, but their positions can still be moved as today.

### Link Creation

When the user creates a link in Delegation Tree mode between two agent nodes, default the link to:

```json
{
  "direction": "one_way",
  "relationship": "hierarchical",
  "communicationType": "task"
}
```

The UI should still allow switching back to Map mode for peer, chat, discussion, or exploratory links.

### Preview Panel

Delegation Tree mode adds a preview panel in the inspector:

- selected root;
- depth levels;
- actor display names;
- linked agent ids;
- validation status;
- warnings and blocking errors.

Example:

```text
Root: Product Lead
Depth 1: iOS Engineer, Backend Engineer
Depth 2: QA Reviewer
```

### Validation Messages

Blocking errors:

- root is missing;
- root is not an agent node;
- root has no execution children;
- reachable execution tree contains a cycle;
- execution tree references a non-agent node;
- execution tree references an agent node without `linkedAgentId`.

Warnings:

- two-way hierarchical task link ignored by swarm;
- peer or chat links are visible but not execution links;
- action or human nodes are visible but not executable in Delegation Tree mode;
- multiple disconnected execution trees exist on the board.

## Backend API

Add a lightweight preview/validation endpoint:

```text
POST /v1/actors/delegation-tree/preview
```

Request:

```json
{
  "rootActorId": "agent:lead"
}
```

Response:

```json
{
  "status": "valid",
  "rootActorId": "agent:lead",
  "levels": [
    [
      {
        "actorId": "agent:ios",
        "displayName": "iOS Engineer",
        "linkedAgentId": "ios"
      }
    ]
  ],
  "errors": [],
  "warnings": []
}
```

The endpoint should read the saved board and configured agents. It should not mutate the board.

Suggested shared models:

- `ActorDelegationTreePreviewRequest`
- `ActorDelegationTreePreviewResponse`
- `ActorDelegationTreeLevelActor`
- `ActorDelegationTreeIssue`
- `ActorDelegationTreeStatus`

These models belong in `Sources/Protocols/APIModels.swift` near the existing Actor Board models.

## Runtime Integration

Runtime behavior should stay anchored in the existing swarm path:

1. A project task is assigned to the root actor or team.
2. `resolveSwarmTaskDelegation` resolves the effective actor and agent.
3. `startSwarmIfHierarchical` loads the Actor Board.
4. `SwarmCoordinator.buildHierarchy` reads one-way hierarchical task links.
5. `SwarmPlanner` creates subtasks for reachable child levels.
6. `executeSwarm` runs child tasks by depth.

The preview endpoint should mirror `SwarmCoordinator` semantics closely so the Dashboard preview matches runtime behavior. If the preview says a tree is valid, assigning a ready project task to that root should enter the existing swarm flow.

## Error Handling

Preview failures should be ordinary API responses, not runtime crashes:

- invalid payload returns 400;
- missing root returns a valid preview response with blocking errors;
- storage failure returns the existing Actor Board failure style;
- unknown root returns a valid preview response with a blocking error.

Board save behavior should remain unchanged. Invalid execution trees may still be saved because the board is also a general map. Delegation Tree mode blocks execution preview, not persistence.

## Testing

Backend tests:

- valid branching tree returns levels and linked agents;
- root without children returns invalid preview;
- non-agent execution child returns invalid preview;
- agent node without linked agent returns invalid preview;
- cycle returns invalid preview;
- peer/chat/discussion links are ignored with warnings when relevant;
- two-way hierarchical task links are ignored with warnings;
- preview does not mutate `actors/board.json`.

Dashboard tests:

- Delegation Tree link creation sends `task + hierarchical + one_way`;
- root selection calls preview endpoint;
- preview errors render in the inspector;
- adding an existing agent does not prevent adding additional agents;
- mode switch preserves board state.

## Implementation Notes

Keep the first implementation small:

- reuse existing board persistence;
- reuse existing agent picker/dropdown patterns;
- reuse `SwarmCoordinator` rather than creating a second graph traversal;
- do not add template storage yet;
- do not add direct board-run actions yet.

The most important product outcome is that a user can create a root agent, add multiple child agents, see the resulting delegation levels, and understand that assigning a project task to the root will trigger the existing swarm behavior.
