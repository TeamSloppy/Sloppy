# AdaUI Inspection and Automation

The AdaUI surface is designed to be inspection-first. The main goal is to let an MCP client understand the live UI tree before attempting any action.

## Selector model

External callers should prefer `accessibilityIdentifier`.

- `accessibilityIdentifier` is the stable external selector.
- `runtimeId` is returned by the runtime for follow-up calls inside the same session.

If a selector is ambiguous, the runtime returns a structured error with candidate nodes. If a selector does not match anything, the runtime returns a stable not-found error.

## Inspection tools

The core read tools are:

- `ui.list_windows`
- `ui.get_window`
- `ui.get_tree`
- `ui.get_node`
- `ui.find_nodes`
- `ui.hit_test`
- `ui.get_layout_diagnostics`

These tools return stable DTOs such as `UIWindowSummary`, `UIWindowSnapshot`, `UINodeSummary`, `UINodeSnapshot`, `UIHitTestResult`, and `UILayoutDiagnostics`.

## AdaUI resources

The same surface is available through resources:

- `ada://ui/windows`
- `ada://ui/window/{windowId}`
- `ada://ui/tree/{windowId}`
- `ada://ui/node/{windowId}/{nodeRef}`

`nodeRef` supports:

- `accessibility:<id>`
- `runtime:<object-identifier>`

## Safe actions

Version 1 intentionally limits automation to deterministic actions:

- `ui.focus_node`
- `ui.focus_next`
- `ui.focus_previous`
- `ui.scroll_to_node`
- `ui.tap_node`
- `ui.set_debug_overlay`

These are designed to work on resolved nodes, not on arbitrary event injection.

## Debug overlays

`ui.set_debug_overlay` controls developer-facing drawing modes:

- `off`
- `layout_bounds`
- `focused_node`
- `hit_test_target`

The overlay uses the existing debug drawing path inside AdaUI rather than a parallel renderer.

## Explicit non-goals for v1

The current surface does not expose:

- arbitrary coordinate-based event injection
- raw keyboard event synthesis
- direct text entry APIs such as `ui.type_text`

Those workflows need a stricter contract around focus ownership and text input semantics. For now, the safe pattern is inspection, deterministic action, and verification.

## Typical workflow

```json
{
  "sequence": [
    "ui.list_windows",
    "ui.find_nodes(accessibilityIdentifier: \"button.primary\")",
    "ui.get_layout_diagnostics(accessibilityIdentifier: \"button.primary\")",
    "ui.tap_node(accessibilityIdentifier: \"button.primary\")",
    "ui.get_tree"
  ]
}
```

This keeps the MCP client grounded in the live tree instead of guessing from screen coordinates.
