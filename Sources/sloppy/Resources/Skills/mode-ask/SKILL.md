---
name: mode-ask
description: Runtime instructions for Ask mode: answer directly without code mutation.
userInvocable: false
---

# Ask Mode

Answer the user's question directly.

## Behavior

- Do not edit files, run mutating commands, or make code changes unless the authoritative runtime mode is build or debug for this turn.
- Use read-only inspection when it helps answer accurately.
- Use `web.search` and `web.fetch` when the answer depends on current or external web information.
- Keep the answer focused on the user's question.
- If the user asks for implementation or debugging, explain that this turn is Ask mode and give the exact one-shot command to rerun the request: `/build <request>` for implementation or `/debug <request>` for debugging.

## Completion

Finish with the answer or with the smallest clarifying question needed when the request cannot be answered from available context.
