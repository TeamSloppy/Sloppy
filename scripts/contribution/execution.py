"""Bounded process execution with compact, non-secret result records."""

from dataclasses import dataclass, field
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time


@dataclass
class Check:
    name: str
    category: str
    argv: list = field(default_factory=list)
    cwd: str = "."
    timeout: int = 900
    reason: str = ""
    status: str = ""
    tests: bool = False
    env: dict = field(default_factory=dict)
    required_output: list = field(default_factory=list)
    ci_targets: list = field(default_factory=list)


def tool_state(root=None):
    result = {"python": sys.version, "platform": platform.platform(), "executable": sys.executable}
    packages = sorted((distribution.metadata.get("Name", ""), distribution.version)
                      for distribution in importlib.metadata.distributions())
    result["installed_packages_sha256"] = hashlib.sha256(json.dumps(packages).encode()).hexdigest()
    for package in ("ruff", "bandit", "detect-secrets", "pip-audit"):
        try:
            result[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            result[package] = None
    for name in ("swift", "swiftlint", "node", "bash"):
        executable = shutil.which(name)
        if executable:
            info = Path(executable).stat()
            result[name] = [executable, info.st_size, info.st_mtime_ns]
    if root is not None:
        # Installed JS code is ignored by Git but can change compiler/build/test behavior.
        # Hash contents, not only package versions or the node executable.
        for folder in ("Dashboard/node_modules", "docs/node_modules"):
            directory = Path(root) / folder
            digest = hashlib.sha256()
            inputs = [directory / ".package-lock.json"]
            for package in ("typescript", "vite", "vitepress", "@vitejs/plugin-vue"):
                base = directory / package
                inputs.append(base / "package.json")
                for child in ("bin", "lib", "dist"):
                    if (base / child).is_dir():
                        inputs.extend(p for p in (base / child).rglob("*") if p.is_file())
            for path in sorted(set(inputs)):
                digest.update(path.relative_to(directory).as_posix().encode())
                digest.update(hashlib.sha256(path.read_bytes()).digest() if path.is_file() else b"<missing>")
            result[folder] = digest.hexdigest() if directory.is_dir() else None
    return result


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def has_executed_tests(output):
    unittest_run = re.search(r"Ran (\d+) tests?", output)
    if unittest_run:
        skipped = re.search(r"\bskipped=(\d+)", output)
        return int(unittest_run[1]) > (int(skipped[1]) if skipped else 0)
    if re.search(r"(?:^|\n)# tests \d+", output):
        return bool(re.search(r"(?:^|\n)# pass [1-9]\d*", output))
    patterns = (
        r"Test run with ([1-9]\d*) tests? .*passed", r"Executed ([1-9]\d*) tests?",
        r"(?:^|\n)# pass ([1-9]\d*)",
    )
    return any(re.search(pattern, output) for pattern in patterns)


def _stop(process):
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, timeout=15, check=False)
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
    process.wait(timeout=15)


def execute(check, root, logs):
    start = time.monotonic()
    result = {"name": check.name, "category": check.category, "status": check.status,
              "reason": check.reason, "command": check.argv, "cwd": check.cwd,
              "environment": check.env, "required_output": check.required_output, "ci_targets": check.ci_targets}
    if check.status:
        return result
    log = Path(logs) / (check.name + ".log")
    log.parent.mkdir(parents=True, exist_ok=True)
    result["log"] = str(log)
    try:
        with log.open("wb") as output:
            process = subprocess.Popen(
                check.argv, cwd=Path(root) / check.cwd, stdout=output, stderr=subprocess.STDOUT,
                env={**os.environ, **check.env, "PYTHONUTF8": "1"},
                start_new_session=os.name != "nt",
            )
            try:
                result["exit_code"] = process.wait(timeout=check.timeout)
            except subprocess.TimeoutExpired:
                _stop(process)
                result.update(status="blocked", reason="Check timed out; its process tree was terminated")
        if not result["status"]:
            code = result["exit_code"]
            result["status"] = "passed" if code == 0 else ("blocked" if code == 2 else "failed")
            if code:
                result["reason"] = "Command returned exit code " + str(code)
            else:
                text = log.read_text(encoding="utf-8", errors="replace")
                if check.tests and not has_executed_tests(text):
                    result.update(status="blocked", reason="No positive test count found; empty or skipped test run")
                if any(not re.search(pattern, text) for pattern in check.required_output):
                    result.update(status="blocked", reason="Required runtime/test execution evidence is missing")
    except (FileNotFoundError, PermissionError) as error:
        result.update(status="blocked", reason=type(error).__name__ + ": required executable or working directory unavailable")
    result["duration_seconds"] = round(time.monotonic() - start, 3)
    if log.exists():
        result["log_sha256"] = hashlib.sha256(log.read_bytes()).hexdigest()
    return result
