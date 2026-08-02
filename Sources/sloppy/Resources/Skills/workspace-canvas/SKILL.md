---
name: workspace-canvas
description: Create and edit Sloppy AI Workspaces with safe, structured, realtime canvas transactions.
---

# Workspace Canvas

Use this skill whenever the user asks to create, inspect, arrange, or edit an AI Workspace.

## Required workflow

1. Call `workspaces.list` when the target workspace is unknown.
2. Call `workspace.get` or `workspace.elements.query` before every edit. Never guess element ids, revisions, or current positions.
3. Plan the smallest coherent change and submit it with `workspace.transaction.apply`.
4. Include the current revision of every updated or deleted element in `expectedRevisions`.
5. After a layout affecting more than five elements, query the affected region and check bounds for accidental overlap.
6. If the tool returns `workspace_conflict`, reread only the conflicting elements, reconsider the change, and retry with their new revisions.

## Spatial rules

- Use a 24 px base spacing unit and keep at least 32 px between unrelated elements.
- Frames contain related work; groups represent a temporary editing relationship.
- Prefer connectors to positional implication when a relationship matters.
- Keep text readable at the default zoom: sticky notes should normally be at least 220×140 and tables at least 420×240.
- Preserve existing layout language, colors, frame alignment, and z-order unless the user requests a redesign.

## Widgets and templates

- Use `workspace.template.list` before recreating a common board pattern.
- Use `artifacts.widget.generate` for self-contained web widgets, then `workspace.artifact.place`.
- Widgets must remain self-contained and must not load external network resources.
- Save a reusable result with `workspace.template.save` only when the user asks or the workspace is clearly intended as a repeatable template.

## Safety

- Never archive a workspace or change its members through content-editing tools.
- Avoid broad deletes. If a deletion affects more than ten elements, explain the scope and use the approval path.
- Keep each transaction atomic: either the whole visual intent succeeds or none of it does.
