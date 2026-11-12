#!/usr/bin/env python3
"""Load a fresh, loopback-only Sloppy instance with HTTP traffic and runtime workers."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
import http.client
import json
import os
from pathlib import Path
import resource
import secrets
import socket
import subprocess
import sys
import tempfile
import time


ACP_FIXTURE = """
import json
import os
from pathlib import Path
import sys
import time
import uuid

def send(payload):
    print(json.dumps({"jsonrpc": "2.0", **payload}), flush=True)

for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message:
        continue
    method = message["method"]
    if method == "initialize":
        result = {"protocolVersion": 1, "agentCapabilities": {}}
    elif method == "session/new":
        session_id = str(uuid.uuid4())
        result = {"sessionId": session_id}
    elif method == "session/prompt":
        time.sleep(1.5)
        Path(os.environ["SLOPPY_STRESS_RECEIPTS"], session_id).touch()
        result = {"stopReason": "end_turn"}
    else:
        send({"id": message["id"], "error": {"code": -32601, "message": "Method not found"}})
        continue
    send({"id": message["id"], "result": result})
"""


def request(connection, method, path, token, body=None):
    connection.request(method, path, body, {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    response = connection.getresponse()
    return response.status, response.read()


def wait_until_ready(server, port, token):
    deadline = time.monotonic() + 30
    while server.poll() is None and time.monotonic() < deadline:
        with closing(http.client.HTTPConnection("127.0.0.1", port, timeout=1)) as connection:
            try:
                if request(connection, "GET", "/health", token)[0] == 200:
                    return
            except (OSError, http.client.HTTPException):
                pass
        time.sleep(0.1)
    raise RuntimeError(f"Server failed readiness (exit status {server.poll()})")


def wait_for_acp_replies(connection, token, sessions):
    pending = set(sessions)
    deadline = time.monotonic() + 45
    while pending and time.monotonic() < deadline:
        for session in list(pending):
            status, body = request(connection, "GET", session, token)
            if status != 200:
                raise RuntimeError(f"Session returned HTTP {status}")
            for event in json.loads(body)["events"]:
                message = event.get("message") or {}
                if message.get("role") == "assistant":
                    pending.remove(session)
                    break
        if not pending:
            return
        time.sleep(0.2)
    raise RuntimeError(f"{len(pending)} ACP sessions did not answer")


def run_load(args, server, port, token, sessions):
    def new_connection(timeout=2):
        return http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)

    def send(connection, acp_connection, index):
        start = time.monotonic()
        worker_index = index * args.workers // args.requests
        submission = (index + 1) * args.workers // args.requests > worker_index
        path = "/health"
        body = None
        if submission and args.acp:
            connection = acp_connection
            path = sessions[worker_index] + "/messages"
            body = json.dumps({"userId": "local", "content": "Reply Done", "attachments": [], "spawnSubSession": False})
        elif submission:
            path = "/v1/workers"
            body = json.dumps({"spec": {
                "taskId": f"stress-{index}", "channelId": "stress",
                "title": "Stress test", "objective": "Wait for input",
                "mode": "interactive", "tools": [],
            }})
        try:
            status, _ = request(connection, "POST" if submission else "GET", path, token, body)
            outcome = str(status)
        except (OSError, http.client.HTTPException) as error:
            connection.close()
            errno = getattr(error, "errno", None)
            outcome = type(error).__name__ if errno is None else f"{type(error).__name__}({errno})"
        return outcome, time.monotonic() - start

    def send_batch(first):
        with closing(new_connection()) as connection, closing(new_connection(timeout=25)) as acp_connection:
            return [send(connection, acp_connection, index) for index in range(first, args.requests, args.concurrency)]

    def probe_during_acp(futures):
        probes = failures = 0
        with closing(new_connection()) as probe:
            while not all(future.done() for future in futures):
                probes += 1
                try:
                    if request(probe, "GET", "/health", token)[0] != 200:
                        failures += 1
                except (OSError, http.client.HTTPException):
                    failures += 1
                    probe.close()
                time.sleep(0.1)
        print(f"Health while ACP requests are pending: {probes - failures}/{probes} successful")
        return failures == 0

    established_health = None
    with ExitStack() as sockets:
        held = 0
        established = None
        for _ in range(args.connections):
            connection = sockets.enter_context(closing(new_connection()))
            try:
                status, _ = request(connection, "GET", "/health", token)
                if status != 200 or connection.sock is None:
                    break
                held += 1
                if established is None:
                    established = connection
            except (OSError, http.client.HTTPException):
                break
        print(f"Held HTTP connections: {held}/{args.connections}", flush=True)

        start = time.monotonic()
        with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
            futures = [executor.submit(send_batch, first) for first in range(min(args.concurrency, args.requests))]
            healthy_during_acp = not args.acp or probe_during_acp(futures)
            results = [result for future in futures for result in future.result()]
        elapsed = time.monotonic() - start
        if established is not None:
            established_health, _ = request(established, "GET", "/health", token)
            print(f"Existing connection under load: health {established_health}")
        if args.acp and all(outcome == "200" for outcome, _ in results):
            with closing(new_connection()) as connection:
                wait_for_acp_replies(connection, token, sessions)

    counts = Counter(outcome for outcome, _ in results)
    latencies = sorted(latency for _, latency in results)
    p95 = latencies[int(0.95 * (len(latencies) - 1))] * 1000
    print(f"{args.requests / elapsed:.0f} requests/s attempted, p95 {p95:.1f} ms, outcomes {dict(counts)}")

    wait_until_ready(server, port, token)
    with closing(new_connection()) as connection:
        health, _ = request(connection, "GET", "/health", token)
        if args.acp:
            print(f"After releasing connections: health {health}")
            return held == args.connections and healthy_during_acp and health == 200 and counts["200"] == args.requests
        status, body = request(connection, "GET", "/v1/workers", token)
        workers = len(json.loads(body)) if status == 200 else 0
    print(f"After releasing connections: health {health}, workers {workers}/{args.workers}")
    if args.expect_saturation:
        return 0 < held < args.connections and established_health == 200 and health == 200
    return (
        held == args.connections and health == 200 and workers == args.workers
        and (established is None or established_health == 200)
        and counts["201"] == args.workers and counts["200"] == args.requests - args.workers
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--connections", type=int, default=480)
    parser.add_argument("--concurrency", type=int, default=64)
    parser.add_argument("--requests", type=int, default=2500)
    parser.add_argument("--workers", type=int, default=256, help="Number of worker submissions or ACP sessions")
    parser.add_argument("--soft-limit", type=int, default=256, help="Initial server RLIMIT_NOFILE")
    parser.add_argument("--hard-limit", type=int, help="Optional hard cap for the test server")
    parser.add_argument("--expect-saturation", action="store_true", help="Verify recovery after hitting a hard cap")
    parser.add_argument("--acp", action="store_true", help="Run agent sessions in local ACP fixture subprocesses")
    args = parser.parse_args()
    if args.requests <= 0 or args.concurrency <= 0 or args.connections < 0 or not 0 <= args.workers <= args.requests:
        parser.error("Invalid request, worker, or connection counts")
    if args.soft_limit <= 0 or (args.hard_limit is not None and args.hard_limit < args.soft_limit):
        parser.error("Invalid file descriptor limits")
    if args.acp and (args.expect_saturation or not args.workers):
        parser.error("ACP mode requires workers and is intended for the successful-load scenario")

    def set_initial_limit():
        _, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        resource.setrlimit(resource.RLIMIT_NOFILE, (args.soft_limit, args.hard_limit or hard))

    with closing(socket.socket()) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]

    binary = args.binary.resolve(strict=True)
    workspace = Path(tempfile.mkdtemp(prefix="sloppy-stress-"))
    token = secrets.token_hex(24)
    config = workspace / "config.json"
    settings = {
        "listen": {"host": "127.0.0.1", "port": port},
        "auth": {"token": token},
        "workspace": {"basePath": str(workspace), "name": "runtime"},
        "memory": {"backend": "sqlite-local-vectors"},
        "coffeeMode": {"enabled": False, "preventDisplaySleep": False, "privilegedLidModeRequired": False},
        "sqlitePath": "core.sqlite",
        "disableModelInference": True,
    }
    environment = {"PATH": os.defpath}
    receipts = workspace / "acp-receipts"
    if args.acp:
        # Reproduce a slow cold shell load without reading the user's shell profile.
        shell = workspace / "fixture-shell"
        shell.write_text("#!/bin/sh\nsleep 6\nexec /usr/bin/env\n")
        shell.chmod(0o700)
        environment["SHELL"] = str(shell)
        receipts.mkdir()
        settings["acp"] = {"enabled": True, "targets": [{
            "id": "fixture", "command": sys.executable, "arguments": ["-u", "-c", ACP_FIXTURE],
            "cwd": str(workspace), "permissionMode": "deny",
            "environment": {"SLOPPY_STRESS_RECEIPTS": str(receipts)},
        }]}
    config.write_text(json.dumps(settings))
    logs = workspace / "server.log"
    print(f"Server log: {logs}", flush=True)
    with logs.open("wb") as output, subprocess.Popen(
        [binary, "run", "--no-gui", "--no-bootstrap-bulletin", "--config-path", config],
        cwd=workspace,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=output,
        stderr=subprocess.STDOUT,
        preexec_fn=set_initial_limit,
    ) as server:
        try:
            wait_until_ready(server, port, token)
            sessions = []
            if args.acp:
                with closing(http.client.HTTPConnection("127.0.0.1", port, timeout=2)) as connection:
                    status, body = request(connection, "POST", "/v1/agents", token, json.dumps({
                        "id": "fixture", "displayName": "Stress fixture", "role": "Exercise agent lifecycle",
                        "isSystem": False, "runtime": {"type": "acp", "acp": {"targetId": "fixture"}},
                    }))
                    if status != 201:
                        raise RuntimeError(f"Could not create ACP fixture agent: HTTP {status} {body!r}")
                    for index in range(args.workers):
                        path = "/v1/agents/fixture/sessions"
                        status, body = request(connection, "POST", path, token, json.dumps({"title": f"Stress {index}"}))
                        if status != 201:
                            raise RuntimeError(f"Could not create ACP session: HTTP {status} {body!r}")
                        sessions.append(f"{path}/{json.loads(body)['id']}")
            passed = run_load(args, server, port, token, sessions)
            if args.acp:
                completed = sum(1 for _ in receipts.iterdir())
                print(f"ACP sessions completed: {completed}/{len(sessions)}")
                passed = passed and completed == len(sessions)
        finally:
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
