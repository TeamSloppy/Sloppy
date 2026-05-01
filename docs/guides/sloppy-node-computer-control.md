# SloppyNode Computer Control

`SloppyNode` can execute machine-facing JSON requests for basic computer control:

```bash
printf '{"action":"status","payload":{}}' | swift run SloppyNode invoke --stdin
```

Supported v1 actions are:

- `computer.click`
- `computer.typeText`
- `computer.key`
- `computer.screenshot`
- `exec`

The Core runtime exposes these as agent tools:

- `computer.click`
- `computer.type`
- `computer.key`
- `computer.screenshot`

Coordinates are absolute screen coordinates in physical pixels. When `width` and `height` are provided for a click, SloppyNode clicks the rectangle center.

## macOS permissions

macOS requires explicit permissions before another process can control input or capture the display:

- Accessibility: required for click and key events.
- Input Monitoring: may be required for keyboard event delivery depending on system policy.
- Screen Recording: required for screenshots.

Grant these permissions to the built `SloppyNode` binary or to the terminal app that launches it, then restart the launcher before retrying.

## Windows notes

Windows support uses the local desktop session. Click, keyboard input, and screenshots only operate reliably when SloppyNode runs in an interactive user session.

## Unsupported platforms

On other platforms, SloppyNode returns a structured `unsupported_platform` error for computer-control actions.
