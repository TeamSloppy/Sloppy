# Continuing a subagent

For another iteration of the same task, the coordinator should prefer the existing
worker in the same chat. It explicitly selects the session; Sloppy does not match
roles or silently create replacements. A fresh session remains useful for an
independent review.

In an ordinary chat, `agents.delegate_task` returns `sessionId` alongside each new
worker's summary. Discover other workers with `sessions.list`. Continue one with:

```json
{
  "sessionId": "session-existing-reviewer",
  "goal": "Check the fixes against your previous review findings"
}
```

Use a single `goal`, optional `context`, and omit `tasks` and `toolsets`. Creation
keeps its existing synchronous result; continuation returns an accepted assignment
immediately. Acceptance means queued, not completed. Status and results are
recorded separately for each assignment and delivered to the parent chat.

In a long chat, set `reuseSessionId` on a new task in `long_chat.delegate`.
`long_chat.status` includes worker session IDs. Keep the original `projectId` and
`resourceKeys`; a read-only worker cannot become a writer. Use `long_chat.message`
to clarify an existing task, and a new delegation to start another iteration.

The worker retains its conversation history. Each iteration has its own task ID,
status, evidence and result. Earlier completion events cannot complete a later
iteration. Tasks for one session run in queue order, including read-only tasks;
independent workers retain the existing concurrency and resource-lock rules.

History, pending assignments, original tool scope and execution directories persist
across Core restarts. Active execution interrupted by a restart is reported as
interrupted rather than blindly replayed. Pending iterations remain queued.
Permissions are checked again at execution and intersected with the original
tool scope. Automatic retention preserves reusable workers while their parent
chat exists.

A missing/deleted session, another chat's worker, unavailable original execution
context or an expanded scope produces an error. The coordinator must explicitly
decide whether to create a replacement. Workers created before execution context
was persisted may therefore be unavailable for continuation; their history remains
readable through the session tools.
