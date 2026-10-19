#!/usr/bin/env python3
"""Paired live Sloppy benchmark. Isolated Core, synthetic MCP, real configured Codex OAuth.

No keys/tokens are included in reports. The temporary OAuth copy has no refresh token.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

MODEL = "openai-oauth:gpt-6.1-sol"
ROOT = Path(__file__).resolve().parents[2]
TARGETS = [
    ("inventory_stock", "Read current on-hand stock for a single SKU at a warehouse. Returns quantity and a verification receipt.",
     {"sku": "string", "warehouse": "string"}, {"sku": "SKU-271", "warehouse": "west"}),
    ("incident_status", "Read the current severity and status of a production incident identified by incident_id. Returns a verification receipt.",
     {"incident_id": "string", "environment": "string"}, {"incident_id": "INC-177", "environment": "production"}),
    ("artifact_digest", "Read the cryptographic digest of a build artifact identified by artifact_ref. Choose the hash algorithm. Returns a verification receipt.",
     {"artifact_ref": "string", "algorithm": "string"}, {"artifact_ref": "build/alpha", "algorithm": "sha256"}),
]
TASKS = [
    "Read the current stock for SKU-271 in warehouse west.",
    "Read the status of production incident INC-177 in environment production.",
    "Read the sha256 digest of artifact build/alpha.",
]

def catalog(size):
    tools = []
    for name, desc, fields, _ in TARGETS:
        tools.append({"name": name, "description": desc, "annotations": {"readOnlyHint": True},
                      "inputSchema": {"type": "object", "properties": {k: {"type": v} for k, v in fields.items()},
                                      "required": list(fields), "additionalProperties": False}})
    domains = ["inventory", "incident", "artifact", "project", "deployment", "audit", "billing", "telemetry"]
    for i in range(size - len(tools)):
        domain = domains[i % len(domains)]
        tools.append({"name": f"{domain}_batch_report_{i:03}",
                      "description": f"Read a historical {domain} batch report with aggregate counts, pagination and archived labels. This report does not return live individual object state or cryptographic hashes.",
                      "annotations": {"readOnlyHint": True},
                      "inputSchema": {"type": "object", "properties": {
                          "batch_id": {"type": "string", "description": "Stable identifier of a previously generated report batch."},
                          "page": {"type": "integer", "description": "Zero-based page index of the archived report."},
                          "include_archived": {"type": "boolean", "description": "Include historical and archived report rows."}},
                          "required": ["batch_id"], "additionalProperties": False}})
    return tools


def mcp_server(path):
    tools = json.loads(path.read_text())
    definitions = {t["name"]: t for t in tools}
    expected = {t[0]: t[3] for t in TARGETS}
    for line in sys.stdin:
        req = json.loads(line)
        method = req.get("method")
        if method == "initialize":
            result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
                      "serverInfo": {"name": "sloppy-live-discovery-fixture", "version": "1"}}
        elif method == "tools/list":
            result = {"tools": tools}
        elif method == "tools/call":
            p = req["params"]
            name, args = p["name"], p.get("arguments", {})
            valid = name in expected and args == expected[name]
            receipt = {"benchmark": "sloppy-tool-discovery-v1", "target": name,
                       "arguments": args, "validated": valid, "receipt": f"verified:{name}" if valid else None}
            result = {"content": [{"type": "text", "text": json.dumps(receipt, sort_keys=True)}], "isError": not valid}
        else:
            result = {}
        if "id" in req:
            print(json.dumps({"jsonrpc": "2.0", "id": req["id"], "result": result}), flush=True)


class Core:
    def __init__(self, state, size, binary=None):
        self.state = state
        self.token = secrets.token_urlsafe(24)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]
        self.base = f"http://127.0.0.1:{self.port}"
        self.workspace = state / "core"
        auth_dir = self.workspace / "auth"
        auth_dir.mkdir(parents=True)
        # Existing working Sloppy OAuth identity, directed only to its configured official endpoint.
        source = Path.home() / ".sloppy/auth/openai-oauth-auth.json"
        auth = json.loads(source.read_text())
        auth["tokens"].pop("refresh_token", None)
        auth_file = auth_dir / "openai-oauth-auth.json"
        auth_file.write_text(json.dumps(auth))
        auth_file.chmod(0o600)
        self.auth_file = auth_file
        self.database = state / "core.sqlite"
        cat_file = state / "catalog.json"
        cat_file.write_text(json.dumps(catalog(size), indent=2))
        self.config = {
            "listen": {"host": "127.0.0.1", "port": self.port},
            "auth": {"token": self.token}, "workspace": {"name": "core", "basePath": str(state)},
            "sqlitePath": str(self.database), "memory": {"backend": "sqlite"},
            "models": [{"title": "Benchmark Codex", "model": MODEL, "providerCatalogId": "openai-oauth",
                        "apiKey": "", "apiUrl": "https://chatgpt.com/backend-api/codex",
                        "contextWindowTokens": 200000, "maxOutputTokens": 2048}],
            "coffeeMode": {"enabled": False, "preventDisplaySleep": False, "privilegedLidModeRequired": False},
            "visor": {"scheduler": {"enabled": False, "intervalSeconds": 3600, "jitterSeconds": 0},
                      "autodream": {"enabled": False, "intervalSeconds": 3600, "jitterSeconds": 0, "sessionLimitPerRun": 4},
                      "bootstrapBulletin": False},
            "mcp": {"servers": [{"id": "catalog", "transport": "stdio", "command": sys.executable,
                                  "arguments": [str(Path(__file__).resolve()), "--mcp", str(cat_file)],
                                  "timeoutMs": 60000, "enabled": True, "exposeTools": True}]},
        }
        cfg = state / "sloppy.json"
        cfg.write_text(json.dumps(self.config))
        cfg.chmod(0o600)
        env = {k: v for k, v in os.environ.items() if not k.startswith(("ANTHROPIC_", "CLAUDE_", "OPENAI_", "CORE_", "SLOPPY_"))}
        self.log = open(state / "core.log", "w")
        self.proc = subprocess.Popen([str(binary or ROOT / ".build/release/sloppy"), "run", "--no-gui", "--config-path", str(cfg)],
                                     cwd=state, env=env, stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                self.close()
                raise RuntimeError(f"Core exited ({self.proc.returncode}); see {state / 'core.log'}")
            try:
                self.request("GET", "/v1/models")
                break
            except Exception:
                time.sleep(0.3)
        else:
            self.close()
            raise RuntimeError("Core startup timed out")

    def request(self, method, path, body=None, timeout=240):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={"Authorization": "Bearer " + self.token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as exc:
            payload = exc.read().decode(errors="replace")
            raise RuntimeError(f"Core HTTP {exc.code}: {payload[:500]}") from None

    def agent(self, arm, size):
        agent = f"bench-{arm}-{size}"
        self.request("POST", "/v1/agents", {"id": agent, "displayName": "Catalog benchmark", "role": "Read-only synthetic MCP benchmark", "isSystem": False})
        allow = {name: True for name in ["system.search_tools", "mcp.list_tools", "mcp.call_tool"]}
        allow.update({"mcp.catalog." + t["name"]: True for t in catalog(size)})
        self.request("PUT", f"/v1/agents/{agent}/tools", {"defaultPolicy": "deny", "tools": allow,
            "approval": {"policy": "never", "untrustedContextGuard": "off"},
            "guardrails": {"maxExecOutputBytes": 262144, "maxToolCallsPerMinute": 120}})
        return agent

    def usage(self, session):
        if not self.database.exists():
            return []
        with sqlite3.connect(self.database) as db:
            db.row_factory = sqlite3.Row
            return [dict(r) for r in db.execute("SELECT * FROM usage_requests WHERE session_id=? ORDER BY created_at,id", (session,))]

    def close(self):
        if hasattr(self, "proc") and self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGINT)
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait()
        self.log.close()
        # Retain only measurement artifacts, never a reusable OAuth copy.
        self.auth_file.unlink(missing_ok=True)
        (self.state / "local-client.json").unlink(missing_ok=True)
        (self.state / "sloppy.json").unlink(missing_ok=True)


def verify(events, target):
    for event in events:
        r = event.get("toolResult")
        if not r or r.get("tool") != "mcp.call_tool" or not r.get("ok"):
            continue
        data = r.get("data") or {}
        if data.get("isError"):
            continue
        for block in data.get("content", []):
            try:
                receipt = json.loads(block.get("text", ""))
            except (ValueError, TypeError):
                continue
            if receipt.get("benchmark") == "sloppy-tool-discovery-v1" and receipt.get("validated") is True and receipt.get("target") == target:
                return True
    return False


def run(args):
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    state_root = Path(tempfile.mkdtemp(prefix="sloppy-discovery-live-core-"))
    report = {"model": MODEL, "sizes": args.sizes, "trials": args.trials, "state_root": str(state_root),
              "provider": "Sloppy OpenAI Codex OAuth / chatgpt.com", "catalog": "synthetic read-only MCP fixture",
              "usage_source": "Provider input/output/cache-read token counters persisted in usage_requests; complete describes attribution, not token availability",
              "failure_measure": "HTTP errors and typed validated MCP receipts, with raw usage_requests.failed retained for accounting validation; older binaries may misclassify error:null",
              "turns": [], "failures": [], "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    def save():
        (out / "raw-results.json").write_text(json.dumps(report, indent=2))
    save()
    for size_index, size in enumerate(args.sizes):
        state = state_root / str(size)
        state.mkdir()
        core = None
        try:
            core = Core(state, size)
            agents = {arm: core.agent(arm, size) for arm in ["listing", "search"]}
            for trial in range(args.trials):
                order = ["listing", "search"] if (trial + size_index) % 2 == 0 else ["search", "listing"]
                for arm in order:
                    agent = agents[arm]
                    session = core.request("POST", f"/v1/agents/{agent}/sessions", {"title": f"catalog-{size}-trial-{trial}", "separateChat": True})["id"]
                    for turn in range(2):
                        task_index = (trial + turn) % len(TARGETS)
                        route = ("For initial discovery use mcp.list_tools(server=catalog). Do not use system.search_tools."
                                 if arm == "listing" else
                                 "For discovery use system.search_tools with server=catalog and a short English capability query. Do not use mcp.list_tools.")
                        prompt = (f"Synthetic read-only benchmark. {route} If the needed schema was already returned in this conversation, reuse it without rediscovering. "
                                  "You must actually execute the matching MCP tool using mcp.call_tool with the exact required arguments. "
                                  "The catalog server is named catalog. Do not guess schemas or use unrelated tools. "
                                  "After the successful tool result, reply with its receipt only. " + TASKS[task_index])
                        prior_usage = {r["id"] for r in core.usage(session)}
                        before = core.request("GET", f"/v1/agents/{agent}/sessions/{session}")
                        prior_events = {e["id"] for e in before.get("events", [])}
                        start = time.monotonic()
                        error = None
                        try:
                            core.request("POST", f"/v1/agents/{agent}/sessions/{session}/messages",
                                         {"userId": "local", "content": prompt, "attachments": [], "spawnSubSession": False, "mode": "ask", "reasoningEffort": "low", "selectedModel": MODEL})
                        except Exception as exc:
                            error = str(exc)
                        elapsed = time.monotonic() - start
                        detail = core.request("GET", f"/v1/agents/{agent}/sessions/{session}")
                        events = [e for e in detail.get("events", []) if e["id"] not in prior_events]
                        usage = [r for r in core.usage(session) if r["id"] not in prior_usage]
                        calls = [e["toolCall"] for e in events if e.get("toolCall")]
                        success = verify(events, TARGETS[task_index][0])
                        row = {"catalog_size": size, "trial": trial, "arm": arm, "turn": turn,
                               "session_id": session, "target": TARGETS[task_index][0], "success": success,
                               "wall_seconds": elapsed, "error": error, "requests": usage, "tool_calls": calls,
                               "events": events, "provider_requests": len(usage),
                               "prompt_tokens": sum(r.get("prompt_tokens") or 0 for r in usage),
                               "completion_tokens": sum(r.get("completion_tokens") or 0 for r in usage),
                               "cached_tokens": sum(r.get("cached_tokens") or 0 for r in usage),
                               "provider_usage_present": bool(usage) and all(r.get("prompt_tokens") is not None and r.get("completion_tokens") is not None for r in usage),
                               "attribution_complete": bool(usage) and all(r.get("complete") for r in usage)}
                        report["turns"].append(row)
                        save()
                        print(json.dumps({k: row[k] for k in ["catalog_size", "trial", "arm", "turn", "success", "wall_seconds", "provider_requests", "prompt_tokens", "cached_tokens", "error"]}), flush=True)
                        if error or not row["provider_usage_present"]:
                            raise RuntimeError("Turn failed or real provider usage was not captured; stopping rather than fabricating counts")
                        total = sum(t["provider_requests"] for t in report["turns"])
                        if total > 96 or sum(t["prompt_tokens"] for t in report["turns"]) > 2_000_000:
                            raise RuntimeError("Measurement safety budget reached")
        except Exception as exc:
            report["failures"].append({"catalog_size": size, "error": str(exc)})
            save()
            raise
        finally:
            if core:
                core.close()
            else:
                (state / "core/auth/openai-oauth-auth.json").unlink(missing_ok=True)
                (state / "sloppy.json").unlink(missing_ok=True)
                (state / "local-client.json").unlink(missing_ok=True)
    report["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    save()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp", type=Path)
    parser.add_argument("--sizes", nargs="+", type=int, default=[16, 128])
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--output", type=Path, default=ROOT / "bench/results/tool-discovery-live-2026-10-18")
    args = parser.parse_args()
    if args.mcp:
        mcp_server(args.mcp)
    else:
        run(args)
