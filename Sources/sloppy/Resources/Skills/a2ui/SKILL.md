---
name: a2ui
description: Create native interactive chat forms, choices and comparisons when several related inputs or a concrete selection help the user continue a task. Not for building a website or changing the Sloppy app.
userInvocable: true
autoRoute: The user wants a form, interactive selection, comparison with a choice, or editable task parameters in chat.
allowedTools: ui.catalog, ui.render, files.read
---

# Interactive chat forms

Use a form when it reduces back-and-forth or makes a decision clearer. A simple answer or a single clarification usually needs text or planning.request_input.

Read ui.catalog first. If the client does not support A2UI, use text. Load [the protocol and examples](references/protocol.md) when composing a surface. Only the advertised component schemas and version are available; never invent widgets, local functions or host actions.

Publish with ui.render: messages is a JSON-array string, expectedRevision is the latest server revision (0 for a new ID), and fallbackText explains the question and offers an ordinary text reply. Use stable IDs for updates. Resolve a revision conflict by reading ui.catalog(surfaceId), retaining relevant user choices, and reconsidering the update. Fix structured validation errors using their path.

Keep each interface small: clear labels, sensible editable defaults, few related fields and one main action. Mark a recommendation as text; never submit it automatically. The client supplies styling and platform layout. Forms must also work with TUI keyboard navigation; tell terminal users they can open the form with Ctrl+Y or /ui.

Publishing is presentation only. It never runs a shell command, edits a ticket, authorizes a tool or marks a task completed. After asking for input, end the current response and wait. Accepted selections arrive as a structured UI action in the same conversation. Use the chosen values and button action to continue; normal tool permissions still apply. Do not infer an action from its visible label.

When the user answers in ordinary text, close or replace obsolete surfaces before continuing. Keep factual options backed by actual sources; do not invent search results or display success before an operation has succeeded. Do not request passwords or tokens in a generated form.
