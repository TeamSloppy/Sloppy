# Interactive forms in chat

Ask an agent to collect a task brief, compare approaches with a choice, or let you edit parameters before continuing. The first-party `/a2ui` skill also makes this workflow explicit. Forms are supported in Dashboard, ClientNative on macOS/iOS, and the terminal client. Older clients and channels receive a text question.

A form can contain text, rows/columns, text or number fields, checkboxes, one-choice pickers and buttons. Required inputs, numeric limits and available choices are checked before sending and again by Core. The host client controls appearance.

In Dashboard and ClientNative, fill the form above the composer and press its action button. Your composer text stays separate. Reloading/reopening restores unfinished values. On a temporary network failure, use Retry send; the client reuses the same action identifier. Once accepted, the form closes and your selected values appear in the original conversation. The agent continues from those values.

In the TUI, press **Ctrl+Y** or enter `/ui` to open pending forms. Use Tab/Shift-Tab to move, arrow keys to choose, Space for a checkbox and Enter to advance or send. Ctrl+N/P switches forms, Ctrl+U clears a text field, and Escape returns to chat while retaining the draft.

You can answer in ordinary text. A submitted form is input to the agent; existing tool approvals still apply to the next operation.

## Agent authoring

Read `ui.catalog` for the current Sloppy catalog and `sloppy/a2ui` references for complete examples. Publish one atomic batch with `ui.render(messages, expectedRevision, fallbackText)`. Start a new surface at revision 0; read the current revision before updating. Keep IDs stable and supply a useful ordinary-text fallback. End the turn after asking for input.

The profile uses A2UI v0.9.1 with catalog `urn:sloppy:a2ui:catalog:v1`. Supported envelopes are createSurface, updateComponents, updateDataModel and deleteSurface. Bindings are distinct, nonoverlapping absolute JSON Pointers. Button actions are symbolic events, delivered to the same agent/session. UI payloads contain no executable scripts, direct tool calls or arbitrary HTML.

## Local acceptance checklist

Use an isolated Core workspace with a test agent and a client advertising `supportsA2UI: true`. The shared fixtures in `Packages/SloppyA2UI/Tests/SloppyA2UITests/Fixtures` exercise three scenarios: brief, comparison and parameters. They are also shipped with the skill.

1. Publish each fixture through `ui.render` with a text fallback. Required fields must block submission; numeric inputs must retain intermediate edits and reject out-of-range values.
2. Enter a composer draft and form values. Reload/reopen, then update server defaults: edited values and composer text must survive.
3. Submit and verify one user action in the same session. Retry the identical UUID/body and expect the same receipt; a changed body or stale revision must return 409.
4. Open a second client, submit once, and verify the other client closes the form. Restart Core and check the accepted state survives.
5. In TUI, complete the same choices using only the keyboard and return to the unchanged composer. On iOS/macOS, verify native fields, scrolling and focus.
6. Check text fallback for an unsupported catalog/client. A publication, replay or history load must never grant a tool approval or automatically submit a choice.

Automated checks: `npm run test:a2ui`, Dashboard typecheck/build, and root `swift test --filter 'a2ui|A2UI'`. Run full Core and native suites separately; a focused pass does not establish that the whole repository is green.
