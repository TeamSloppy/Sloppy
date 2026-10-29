"""Loopback-only sample backend for visually checking the AdaUI client.

Run python scripts/preview-workspace.py, then launch a DEBUG SloppyClient with
SLOPPY_CLIENT_PREVIEW_URL=http://127.0.0.1:25102. Preview preferences are isolated.
All mutations affect only this process's in-memory sample data.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

DATE = "2026-10-27T10:00:00Z"
agents = [{"id": "sloppy", "displayName": "Sloppy", "role": "Coding assistant"},
          {"id": "designer", "displayName": "Designer", "role": "Product design"}]
projects = [
    {"id": "adaengine", "name": "AdaEngine", "description": "A Swift game engine", "directoryPaths": ["D:/Development/AdaEngine"],
     "actors": ["sloppy"], "tasks": [
         {"id": "ADA-1", "title": "Bring the native workspace to AdaUI", "status": "in_progress", "priority": "high", "actorId": "sloppy", "tags": ["client", "ui"]},
         {"id": "ADA-2", "title": "Check keyboard navigation", "status": "needs_review", "priority": "medium"},
         {"id": "ADA-3", "title": "Connect the local engine package", "status": "done"}]},
    {"id": "sloppy", "name": "Sloppy", "description": "Your agent workspace", "actors": ["sloppy"], "tasks": []}]
sessions = [
    {"id": "layout", "agentId": "sloppy", "title": "Refine the workspace layout", "messageCount": 2, "updatedAt": DATE, "kind": "chat", "projectId": "adaengine"},
    {"id": "release", "agentId": "designer", "title": "Plan the next release", "messageCount": 0, "updatedAt": DATE, "kind": "chat"}]
scheduled = [{"id": "morning", "agentId": "sloppy", "channelId": "project", "schedule": "0 9 * * *",
              "command": "Prepare a morning report with confirmed project updates and open reviews.", "enabled": True, "createdAt": DATE, "updatedAt": DATE}]
reviews = [{"id": "12", "providerId": "github", "providerName": "GitHub", "repository": "sample/adaengine", "number": 12,
            "title": "Improve text layout and keyboard focus", "url": "https://example.invalid/review/12", "author": "developer", "state": "open", "isDraft": False,
            "roles": ["review_requested"], "labels": ["ui"], "createdAt": DATE, "updatedAt": DATE}]
diff = "diff --git a/Sources/Workspace.swift b/Sources/Workspace.swift\n--- a/Sources/Workspace.swift\n+++ b/Sources/Workspace.swift\n@@ -1 +1,2 @@\n-let title = \"Workspace\"\n+let title = \"Sloppy\"\n+let showsInspector = true\n"
findings = [{"id": "review-ready", "agentId": "sloppy", "source": {"id": "ADA-2", "kind": "task", "title": "Keyboard navigation", "projectId": "adaengine", "taskId": "ADA-2"},
             "revision": "1", "outcome": "needs_input", "reason": "Keyboard navigation is ready for review", "evidence": "The implementation and checks are complete.",
             "nextStep": "Review focus traversal in the workspace.", "sessionId": "layout", "createdAt": DATE}]
canvases = []
automations = []
documents = {}
automation_runs = []
profile = {"id": "preview-user", "login": "preview", "name": "Preview", "role": "admin", "description": "Local sample account"}
proactive_settings = {"heartbeat": {"enabled": True, "mode": "proactive", "intervalMinutes": 30,
    "proactive": {"projectIds": ["adaengine"], "reviewProviderIds": [], "analysisModel": "preview", "notificationStartHour": 9, "notificationEndHour": 21, "timeZone": "Europe/Moscow"}}, "heartbeatMarkdown": "Check project progress and open reviews."}
config = {"listen": {"host": "127.0.0.1", "port": 25102}, "auth": {"token": ""},
          "memory": {"backend": "sqlite-local-vectors"}, "nodes": ["local"],
          "models": [{"title": "Preview", "apiKey": "", "apiUrl": "http://localhost", "model": "preview"}],
          "browser": {"enabled": False}, "modelRouting": {"fast": "preview"}, "futureServerField": {"keep": True}}
task_comments = [{"id": "comment-1", "taskId": "ADA-1", "content": "## Acceptance\n\n- Open task details\n- Select and copy **Markdown** text\n- Search files with `@`", "authorActorId": "designer", "createdAt": DATE}]
markdown_fixture = """# Markdown on AdaUI

Обычный текст, **жирный**, *курсив* и `inline code`.

- Global navigation and project tools
- Environment and source-control inspector
  - Nested item

3. Scheduled tasks
4. Pull requests

> A quotation with **emphasis**.

```swift
let title = "Sloppy"
print(title)
```

| Feature | State |
| --- | --- |
| Markdown | Ready |
| Selection | Ready |

[AdaEngine documentation](https://adaengine.org)
"""

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, result, code=200):
        payload = json.dumps(result).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        parts = path.split("/")
        if path == "/health": result = {"status": "ok"}
        elif path == "/browser-test":
            payload = b'<!doctype html><html><head><title>Sloppy browser check</title></head><body style="font:24px sans-serif;padding:40px;background:#f5f2e9"><h1>Browser is running</h1><p>Real Chromium inside AdaUI</p><input id="name" placeholder="Type here"><button id="check" onclick="document.querySelector(\'#result\').textContent=\'Clicked: \'+document.querySelector(\'#name\').value">Check</button><p id="result">Ready</p><a href="/browser-next">Next page</a></body></html>'
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.send_header("Content-Length", str(len(payload))); self.end_headers(); self.wfile.write(payload); return
        elif path == "/browser-next":
            payload = b'<html><title>Second page</title><body><h1>Navigation works</h1><a href="/browser-test">Back to test</a></body></html>'
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.send_header("Content-Length", str(len(payload))); self.end_headers(); self.wfile.write(payload); return
        elif path == "/v1/auth/me": result = profile
        elif path == "/v1/tool-approvals/pending": result = []
        elif path == "/v1/channel-approvals/users": result = []
        elif path == "/v1/node/mesh": result = {"nodes": [{"id": "local", "name": "This computer", "status": "connected"}], "links": []}
        elif path == "/v1/voice/config": result = {"enabled": False, "provider": "system"}
        elif path.endswith("/proactivity/settings"): result = proactive_settings
        elif path.endswith("/automation-runs"): result = [r for r in automation_runs if r["projectId"] == parts[3]]
        elif path.startswith("/v1/workspaces/") and path.endswith("/document"):
            result = {"document": documents.get(parts[3], {"workspaceId": parts[3], "schemaVersion": 1, "revision": 0, "elements": [], "connections": []})}
        elif path == "/v1/projects": result = projects
        elif path == "/v1/agents": result = agents
        elif path == "/v1/config": result = config
        elif path == "/v1/providers/models": result = [{"id": "preview", "title": "Preview model", "capabilities": []}]
        elif path == "/v1/agent-sessions":
            query = parse_qs(parsed.query).get("query", [""])[0].lower()
            result = [s for s in sessions if query in s["title"].lower()]
        elif path.endswith("/chat-slash-commands"):
            result = {"commands": [{"source": "builtin", "name": "help", "description": "Show available commands"},
                                   {"source": "builtin", "name": "review", "description": "Review the current changes"},
                                   {"source": "skill", "name": "build", "description": "Build and verify the project", "skillId": "build"}]}
        elif "/tasks/" in path and path.endswith("/comments"): result = [c for c in task_comments if c["taskId"] == parts[5]]
        elif "/tasks/" in path and path.endswith("/activities"):
            result = [{"id": "activity-1", "taskId": parts[5], "field": "status", "oldValue": "ready", "newValue": "in_progress", "actorId": "sloppy", "createdAt": DATE}]
        elif "/tasks/" in path and path.endswith("/logs"): result = []
        elif "/tasks/" in path and path.endswith("/clarifications"): result = []
        elif "/tasks/" in path and path.endswith("/diff"):
            result = {"diff": diff, "branchName": "feature/ui", "baseBranch": "main", "hasChanges": True}
        elif path == "/v1/workspaces": result = {"workspaces": [c for c in canvases if c["projectId"] == parse_qs(parsed.query).get("projectId", [None])[0]]}
        elif path == "/v1/sites": result = {"sites": []}
        elif path == "/v1/code-reviews": result = {"items": reviews, "providers": [{"id": "github", "displayName": "GitHub", "capabilities": []}], "failures": {}}
        elif path.startswith("/v1/code-reviews/"):
            result = {"item": reviews[0], "description": "Improve focus traversal in the workspace.", "sourceBranch": "feature/ui", "targetBranch": "main", "reviewers": [], "comments": [], "diff": diff, "diffTruncated": False}
        elif path.endswith("/proactivity"):
            result = {"findings": findings if parts[3] == "sloppy" else [], "pendingAnalysisCount": 0, "sourceErrors": {}}
        elif path.endswith("/cron"): result = [t for t in scheduled if t["agentId"] == parts[3]]
        elif path.endswith("/automations"): result = [a for a in automations if a["projectId"] == parts[3]]
        elif path.endswith("/source-control/working-tree"):
            result = {"providerId": "git", "isRepository": True, "branch": "main", "linesAdded": 2, "linesDeleted": 1, "diff": diff, "diffTruncated": False}
        elif path.endswith("/files/content"): result = {"path": "Sources/Workspace.swift", "content": "let title = \"Sloppy\"\nlet showsInspector = true\n", "sizeBytes": 57}
        elif path.endswith("/files/search"):
            query = parse_qs(parsed.query).get("q", [""])[0].lower()
            result = [{"path": p, "type": "file"} for p in ["Sources/Workspace.swift", "README.md", "Package.swift"] if query in p.lower()]
        elif path.endswith("/files"): result = [{"name": "Workspace.swift", "path": "Sources/Workspace.swift", "type": "file", "size": 57}]
        elif path.endswith("/sessions"): result = [s for s in sessions if s["agentId"] == parts[3]]
        elif "/sessions/" in path:
            session = next((s for s in sessions if s["id"] == parts[-1]), sessions[0])
            result = {"summary": session, "messages": [
                {"id": "one", "role": "user", "segments": [{"kind": "text", "text": "Bring this workspace to AdaEngine."}], "createdAt": DATE},
                {"id": "two", "role": "assistant", "segments": [{"kind": "text", "text": markdown_fixture}], "createdAt": DATE}]}
        elif path.startswith("/v1/agents/"): result = next((a for a in agents if a["id"] == parts[-1]), agents[0])
        elif path.startswith("/v1/projects/"): result = next((p for p in projects if p["id"] == parts[-1]), projects[0])
        else:
            self.reply({"error": "Preview endpoint not implemented"}, 404)
            return
        self.reply(result)

    def do_POST(self):
        path = urlparse(self.path).path
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if path.startswith("/v1/workspace-browser/"):
            result = {"commands": []} if path.endswith("/poll") else {"status": "connected"}
        elif path.endswith("/sessions"):
            result = {"id": f"session-{len(sessions) + 1}", "agentId": path.split("/")[3], "title": data.get("title", "New chat"), "messageCount": 0, "updatedAt": DATE, "kind": "chat", **data}
            sessions.append(result)
        elif path == "/v1/workspaces":
            result = {"id": str(len(canvases) + 1), "description": "", "revision": 0, **data}
            canvases.append(result)
            documents[result["id"]] = {"workspaceId": result["id"], "schemaVersion": 1, "revision": 0, "elements": [], "connections": []}
        elif path.startswith("/v1/workspaces/") and path.endswith("/transactions"):
            workspace_id = path.split("/")[3]
            document = documents[workspace_id]
            if data["baseRevision"] != document["revision"]:
                self.reply({"error": "revision_conflict"}, 409); return
            for element in document["elements"]:
                if element["id"] in data.get("expectedElementRevisions", {}) and element["revision"] != data["expectedElementRevisions"][element["id"]]:
                    self.reply({"error": "element_conflict"}, 409); return
            document["revision"] += 1
            for operation in data["operations"]:
                element = operation.get("element")
                target = element["id"] if element else operation.get("targetId")
                document["elements"] = [e for e in document["elements"] if e["id"] != target]
                if element:
                    element["revision"] = document["revision"]
                    document["elements"].append(element)
            result = {"id": data["id"], "workspaceId": workspace_id, "revision": document["revision"], "operations": data["operations"]}
        elif path.endswith("/run") and "/automations/" in path:
            automation = next(a for a in automations if a["id"] == path.split("/")[-2])
            run = {"id": f"run-{len(automation_runs) + 1}", "automationId": automation["id"], "projectId": automation["projectId"], "workflowId": automation["workflowId"],
                   "repositoryFullName": automation["repositoryFullName"], "triggerType": "manual", "status": "completed", "summary": "Preview workflow completed successfully.", "startedAt": DATE, "finishedAt": DATE}
            automation_runs.append(run)
            result = {"run": run}
        elif path.endswith("/automations"):
            result = {"id": str(len(automations) + 1), "projectId": path.split("/")[3], "version": 1, "createdAt": DATE, "updatedAt": DATE, **data}
            automations.append(result)
        elif path.endswith("/cron"):
            result = {"id": str(len(scheduled) + 1), "agentId": path.split("/")[3], "enabled": True, "createdAt": DATE, "updatedAt": DATE, **data}
            scheduled.append(result)
        elif path.endswith("/action"):
            result = next(f for f in findings if f["id"] == path.split("/")[-2])
            result[{"read": "readAt", "dismiss": "dismissedAt", "snooze": "snoozedUntil"}[data["action"]]] = "2099-01-01T00:00:00Z"
        elif "/tasks/" in path and path.endswith("/comments"):
            result = {"id": f"comment-{len(task_comments) + 1}", "taskId": path.split("/")[5], "authorActorId": "user", "createdAt": DATE, **data}
            task_comments.append(result)
        else:
            self.reply({"error": "Preview endpoint not implemented"}, 404)
            return
        self.reply(result)

    def do_PUT(self):
        if urlparse(self.path).path.endswith("/proactivity/settings"):
            proactive_settings.update(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))))
            self.reply(proactive_settings); return
        if urlparse(self.path).path == "/v1/config":
            config.clear()
            config.update(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))))
            self.reply(config)
            return
        task_id = urlparse(self.path).path.split("/")[-1]
        task = next((t for t in scheduled if t["id"] == task_id), None)
        if task is None:
            self.reply({"error": "Task not found"}, 404)
            return
        task.update(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))))
        self.reply(task)

    def do_PATCH(self):
        if urlparse(self.path).path == "/v1/auth/me":
            profile.update(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))))
            self.reply(profile); return
        parts = urlparse(self.path).path.split("/")
        if len(parts) == 6 and parts[4] == "tasks":
            project = next((p for p in projects if p["id"] == parts[3]), None)
            task = next((t for t in (project or {}).get("tasks", []) if t["id"] == parts[5]), None)
            if task is not None:
                task.update(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))))
                self.reply(project)
                return
        self.reply({"error": "Task not found"}, 404)

if __name__ == "__main__":
    print("Preview backend: http://127.0.0.1:25102", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 25102), Handler).serve_forever()
