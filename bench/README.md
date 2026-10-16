# Sloppy bench

Disposable-sandbox benchmark for the agent harness.

```
sloppy run --no-gui                      # a Core with a configured model
sloppy bench list --suite smoke
sloppy bench run --agent-id <agentId> --model <modelId> -n 3 --output out.json
sloppy bench run --agent-id <agentId> --model <weakModel> --baseline out.json
```

A task is a directory under `bench/suites/<suite>/<id>/`:

- `repo/` — starting files; copied into a fresh temp dir (with a git baseline) for every attempt.
- `prompt.md` — the user message.
- `check.sh` — run with `bash` inside the sandbox; exit 0 means solved. The baseline must fail it.
- `task.json` — `title`, `tags`, `timeoutSeconds`, `checkTimeoutSeconds`.

Scoring uses only `check.sh`. Metrics (tool calls, typed tool error codes, edit conflicts, tokens)
come from session events, never from assistant text.
