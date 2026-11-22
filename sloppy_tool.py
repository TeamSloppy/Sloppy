#!/usr/bin/env python3
"""Sloppy installation and environment helper. Requires Python 3.9+."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--dry-run", action="store_true", help="Print actions without changing the system")
    root = argparse.ArgumentParser(description="Install Sloppy and check the local environment (Python 3.9+).", parents=[common])
    commands = root.add_subparsers(dest="command", required=True)
    doctor = commands.add_parser("doctor", parents=[common], help="Check installation prerequisites")
    doctor.add_argument("--from-source", action="store_true", help="Also check build prerequisites")
    doctor.add_argument("--json", action="store_true", help="Print a machine-readable report")
    install = commands.add_parser("install", parents=[common], help="Run the existing platform installer")
    mode = install.add_mutually_exclusive_group()
    mode.add_argument("--release", action="store_true", help="Install a prebuilt release (macOS/Linux)")
    mode.add_argument("--from-source", action="store_true", help="Build and install from this checkout")
    install.add_argument("--release-tag", help="Release tag, e.g. v2.5.1 (macOS/Linux)")
    install.add_argument("--install-root", type=Path, help="Destination root (Windows source install)")
    install.add_argument("--no-path", action="store_true", help="Do not modify PATH or shell profiles")
    return root


def check(name: str, ok: bool, detail: str, required: bool = True) -> dict:
    return {"name": name, "ok": bool(ok), "detail": detail, "required": required}


def doctor(args: argparse.Namespace) -> int:
    system = platform.system()
    checks = [check("Python", sys.version_info >= (3, 9), sys.version.split()[0] + "; requires 3.9+"),
              check("Platform", system in ("Darwin", "Linux", "Windows"), system)]
    if system in ("Darwin", "Linux"):
        checks.append(check("Bash", bool(shutil.which("bash")), shutil.which("bash") or "not found"))
        if args.from_source:
            checks.extend([check("Git", bool(shutil.which("git")), shutil.which("git") or "not found"),
                           check("Swift", bool(shutil.which("swift")), shutil.which("swift") or "not found"),
                           check("Node.js", bool(shutil.which("node")), shutil.which("node") or "not found"),
                           check("npm", bool(shutil.which("npm")), shutil.which("npm") or "not found")])
    elif system == "Windows":
        checks.append(check("PowerShell", bool(shutil.which("pwsh") or shutil.which("powershell")), shutil.which("pwsh") or shutil.which("powershell") or "not found"))
        if args.from_source:
            checks.append(check("Git", bool(shutil.which("git")), shutil.which("git") or "not found"))
            # Source bootstrap installs its own build prerequisites; this only checks its launcher.
    ok = all(item["ok"] for item in checks if item["required"])
    if args.json:
        print(json.dumps({"ok": ok, "platform": system, "architecture": platform.machine(), "checks": checks}, indent=2))
    else:
        print(f"Sloppy doctor: {system}/{platform.machine()}")
        for item in checks:
            print(f"[{('OK' if item['ok'] else 'MISSING' if item['required'] else 'INFO')}] {item['name']}: {item['detail']}")
    return 0 if ok else 1


def install(args: argparse.Namespace) -> int:
    system = platform.system()
    if system not in ("Darwin", "Linux", "Windows"):
        print(f"Unsupported platform: {system}", file=sys.stderr)
        return 1
    from_source = args.from_source or (system == "Windows" and not args.release)
    if system == "Windows" and args.release:
        print("Windows release installation is not exposed by the current PowerShell source installer. Use --from-source or the documented Windows release installation flow.", file=sys.stderr)
        return 2
    if system != "Windows" and not from_source and not args.release:
        from_source = False  # Default to the prebuilt release, matching scripts/install.sh.
    if args.release_tag and (system == "Windows" or from_source):
        print("--release-tag applies only to macOS/Linux release installs.", file=sys.stderr)
        return 2
    if args.install_root and system != "Windows":
        print("--install-root is currently supported only for Windows source installs.", file=sys.stderr)
        return 2
    if args.dry_run:
        command = ("PowerShell scripts/install.ps1 -DryRun" if system == "Windows" else "bash scripts/install.sh --dry-run")
        print(f"Would run: {command}" + (" --bundle" if system != "Windows" and from_source else ""))
        return 0
    env = os.environ.copy()
    if args.release_tag:
        env["SLOPPY_RELEASE_TAG"] = args.release_tag
    if system == "Windows":
        script = ROOT / "scripts" / "install.ps1"
        command = [shutil.which("pwsh") or shutil.which("powershell") or "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
        if args.install_root:
            command += ["-InstallRoot", str(args.install_root)]
        if args.no_path:
            command += ["-NoPath"]
    else:
        command = ["bash", str(ROOT / "scripts" / "install.sh")]
        command.append("--bundle" if from_source else "--release")
        if args.no_path:
            command.append("--no-path")
    try:
        return subprocess.run(command, cwd=ROOT, env=env).returncode
    except OSError as error:
        print(f"Unable to start installer: {error}", file=sys.stderr)
        return 1


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < (3, 9):
        print("sloppy_tool.py requires Python 3.9 or newer", file=sys.stderr)
        return 2
    args = parser().parse_args(argv)
    if args.command == "doctor":
        return doctor(args)
    return install(args)


if __name__ == "__main__":
    raise SystemExit(main())
