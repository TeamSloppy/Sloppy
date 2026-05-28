---
name: mode-debug
description: Runtime instructions for Debug mode: investigate with hypotheses, instrumentation, logs, and user feedback.
userInvocable: false
---

# Debug Mode

Improve the existing debug session in a hypothesis-driven loop.

## Hypotheses

- Before adding instrumentation, state the hypotheses you are testing.
- For each hypothesis, name the log fields or observed behavior that would confirm or reject it.

## Instrumentation

- Add focused diagnostic logging or instrumentation to the code so the behavior can be understood.
- Then run or describe the smallest check that would produce useful evidence.
- Wrap every temporary diagnostic block you add with exactly `// #region agent debug` before it and `// #endregion` after it.
- Write temporary agent logs as NDJSON under the repository root in `.sloppy/debug/debug-<shortSessionId>.log`; the runtime creates `.sloppy/debug` for debug turns before tool execution.
- Each log line should include `sessionId`, `timestamp`, `hypothesisId`, `location`, `message`, and optional `data`.

## User Reproduction Loop

- Before pausing for the user, always show the exact log path and a short `Reproduction steps` section.
- Use `planning.request_input` to pause with options `proceed` labeled `Proceed`, `bug_repeated` labeled `Bug is repeated`, and `mark_as_fixed` labeled `Mark as fixed`; then wait.
- If the user selects `proceed`, read the log path you provided, prefer `debug.read_logs` for NDJSON summaries, and classify each hypothesis as `CONFIRMED`, `REJECTED`, or `INCONCLUSIVE` using fields from the logs.
- If the logs make the root cause clear, implement the smallest fix, then repeat the loop: update or remove instrumentation as needed, ask the user to reproduce, and compare the new logs.
- If the user selects `bug_repeated`, continue investigating with the debug regions still available and refine the hypotheses or logging.
- If the user selects `mark_as_fixed`, remove the session log file and every `// #region agent debug`...`// #endregion` block you added before finishing.
