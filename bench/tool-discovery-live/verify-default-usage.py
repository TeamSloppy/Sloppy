#!/usr/bin/env python3
"""Verify the default MCP route, optional search and usage failure flags on a real provider."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import time

from run import Core, MODEL, ROOT, TARGETS, TASKS, verify


def run(binary, output):
    binary = binary.resolve()
    state = Path(tempfile.mkdtemp(prefix="sloppy-default-usage-live-"))
    report = {
        "model": MODEL,
        "provider": "Sloppy OpenAI Codex OAuth / chatgpt.com",
        "catalog": "16 synthetic read-only MCP tools",
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "state_root": str(state),
        "turns": [],
    }
    core = None
    try:
        core = Core(state, 16, binary=binary)
        agent = core.agent("default-usage", 16)
        for route in ["default", "explicit-search"]:
            session = core.request("POST", f"/v1/agents/{agent}/sessions",
                                   {"title": route, "separateChat": True})["id"]
            prompt = ("Synthetic read-only task. The MCP server is named catalog. "
                      "Actually execute the matching MCP tool with its required arguments. "
                      "After the successful result, reply with its receipt only. " + TASKS[0])
            if route == "explicit-search":
                prompt += " Use system.search_tools to find the exact inventory_stock schema before calling it."
            start = time.monotonic()
            core.request("POST", f"/v1/agents/{agent}/sessions/{session}/messages", {
                "userId": "local", "content": prompt, "attachments": [], "spawnSubSession": False,
                "mode": "ask", "reasoningEffort": "low", "selectedModel": MODEL,
            })
            detail = core.request("GET", f"/v1/agents/{agent}/sessions/{session}")
            events = detail.get("events", [])
            usage = core.usage(session)
            calls = [e["toolCall"]["tool"] for e in events if e.get("toolCall")]
            expected = "mcp.list_tools" if route == "default" else "system.search_tools"
            forbidden = "system.search_tools" if route == "default" else "mcp.list_tools"
            row = {
                "route": route,
                "session_id": session,
                "wall_seconds": time.monotonic() - start,
                "tool_calls": calls,
                "validated_receipt": verify(events, TARGETS[0][0]),
                "expected_route": expected in calls and forbidden not in calls and "mcp.call_tool" in calls,
                "requests": usage,
                "usage_present": bool(usage) and all(r.get("prompt_tokens") is not None and
                                                     r.get("completion_tokens") is not None for r in usage),
                "no_failed_requests": bool(usage) and all(r["failed"] == 0 for r in usage),
            }
            report["turns"].append(row)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({k: v for k, v in row.items() if k != "requests"}), flush=True)
            if not all(row[k] for k in ["validated_receipt", "expected_route", "usage_present", "no_failed_requests"]):
                raise RuntimeError(f"Live verification failed for {route}; see {output}")
    finally:
        if core:
            core.close()
        else:
            (state / "core/auth/openai-oauth-auth.json").unlink(missing_ok=True)
            (state / "sloppy.json").unlink(missing_ok=True)
            (state / "local-client.json").unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=ROOT / ".build/debug/sloppy")
    parser.add_argument("--output", type=Path, default=ROOT / "bench/results/tool-discovery-live-2026-10-18/default-usage-verification.json")
    args = parser.parse_args()
    run(args.binary, args.output.resolve())
