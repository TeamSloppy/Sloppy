# Autonomous session goals

Use `/goal <objective>` in the native chat, Dashboard, or TUI to start or replace an autonomous goal in the current conversation. State a result that can be checked, such as finishing an approved workflow and verifying its remaining steps.

The server handles graphical chat commands before model inference. Starting a goal preserves the selected model, reasoning settings, attachments, and session references. The original command remains in chat history.

| Command | Effect |
| --- | --- |
| `/goal <objective>` | Start or replace the session goal. |
| `/goal status` | Show its objective, state, and attempt count. |
| `/goal pause` | Prevent future automatic continuation. |
| `/goal resume` | Continue a paused goal or one waiting for input. |
| `/goal clear` | Remove the session goal. |

Pause prevents queued goal turns from starting; it does not cancel an already running worker. Use the existing stop/cancel controls to stop execution. Goal state is saved with the workspace and restored when accessed after a server restart.

In a long chat, the coordinator delegates implementation to workers. The goal waits for their notifications instead of polling or repeatedly spawning work. A coordinator's completion report cannot complete the goal while its delegated tasks are unfinished. Once those tasks finish, their notifications let the coordinator verify the result and continue the approved workflow. Completion and waiting states use structured runtime events, rather than matching phrases in model replies.

Automatic continuation is bounded by the goal's attempt limit (eight by default). An explicit completion, blocker, request for input, pause, or clear stops continuation. `/goal task` and `/goal bg` remain TUI shortcuts for project tasks; graphical chats can use `/task`.
