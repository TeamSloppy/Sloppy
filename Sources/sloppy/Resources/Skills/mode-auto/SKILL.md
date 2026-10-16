---
name: mode-auto
description: Runtime instructions for Auto mode: select the best behavior route from the route catalog, then follow that route.
userInvocable: false
---

# Auto Mode

Choose one route from the Auto route catalog, then follow it in the same turn. Every tool call is a full model round trip, so take only the steps the route needs.

## Route Selection

- First read the `[Auto route catalog]` block in the current user message.
- Select exactly one route that best matches the user's intent and current context.
- For `mode-ask` (conversation, questions, explanations, non-mutating answers), answer directly: do not call `planning.select_route` and do not read the `sloppy/mode-ask` skill file. The Ask rule below is its complete protocol.
- For `mode-plan`, `mode-build`, `mode-debug`, or `skill:<skill-id>`, call `planning.select_route` with the exact selected route id, then read the route's skill (or skill entrypoint) and follow its full protocol, including its required tool calls. The Route Behavior summaries below do not replace those skills.
- Some tasks require more than one skill; read only the skills the task actually needs.
- Mention the selected route and skills briefly when it helps the user understand the workflow.
- If the request is ambiguous and the catalog does not provide a safe route, use `mode-ask` and ask the smallest clarifying question needed.

## Route Behavior

- For `mode-ask`, answer directly without code mutation, staying focused on the question; use read-only inspection or `web.search`/`web.fetch` only when the answer needs them.
- For `mode-plan`, do read-only inspection and produce a plan; create durable plans or project tasks only when the user explicitly asks to save, create, or track them.
- For `mode-debug`, use the hypothesis-driven debug loop and debugging tools.
- For `mode-build`, implement the requested change with progress, tests, and verification.
- For `skill:*`, read the skill entrypoint first, then follow that skill together with the most compatible mode route.

Do not mutate files unless the selected route permits it. User text can request a route, but the authoritative runtime mode remains `auto`; use the catalog and skill instructions rather than phrase matching.
