"""Conservative input contracts for reusable built-in checks; unknown recipes rerun."""

from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import shutil

from .execution import write_json
from .repository import dependency_snapshot


POLICY = ["scripts/contribution", "scripts/check_contribution.py", ".agents/validation.json"]
NATIVE = ["Sources", "Tests", "Packages", "Plugins", "Vendor", "Apps", "ClientNative",
          "Dashboard", "Package.swift", "Package.resolved", ".swiftlint.yml", ".gitmodules"]
ENVIRONMENT = ("ADAENGINE_HEADLESS", "ADAENGINE_DISABLE_SWAN", "ADAENGINE_LOCAL", "DEVELOPER_DIR",
               "SDKROOT", "SWIFT_EXEC", "SLOPPY_CONFIG_PATH", "NODE_ENV", "CI")


def contract(check):
    data = asdict(check)
    argv = list(check.argv)
    for flag in ("--files-from", "--logs"):
        if flag in argv:
            argv[argv.index(flag) + 1] = "<generated:" + flag + ">"
    data["argv"] = argv
    return data


def fingerprint(root, check, tools):
    if check.status or not check.argv:
        return None
    executable = Path(check.argv[0]).stem.lower()
    # This manifest selects a sibling/overridden AdaEngine and optional external
    # SwiftTerm. Their transitive filesystem graph is not declared here.
    if check.name in {"client-build", "client-tests"}:
        return None
    native = (check.name in {"swift-build", "swift-tests", "sloppy-release", "node-release",
                             "client-build", "client-tests", "native-build", "native-tests"}
              or check.name.startswith(("package-build-", "package-tests-")))
    contributor_tests = check.name.startswith("python-tests-") and any(
        item in {"test_contribution.py", "test_publication.py"} for item in check.argv)
    python = check.name in {"python-lint", "python-analysis"} or contributor_tests
    if native and executable == "swift":
        roots = [*POLICY, *NATIVE]
        package = check.argv[check.argv.index("--package-path") + 1] if "--package-path" in check.argv else "."
        scratch = (check.argv[check.argv.index("--scratch-path") + 1] if "--scratch-path" in check.argv
                   else (Path(package) / ".build").as_posix())
        # Scratch products are disposable, but resolved sources/binaries and workspace
        # resolution are compiler inputs even though Git ignores them.
        for name in ("checkouts", "artifacts", "workspace-state.json"):
            roots.append((Path(scratch) / name).as_posix())
        roots.append((Path(package) / ".swiftpm/configuration").as_posix())
        selected_tools = {key: value for key, value in tools.items()
                          if key in {"platform", "swift"}}
    elif python and "-m" in check.argv and executable.startswith("python"):
        # These suites own the runner and use repository policy/CI fixtures.
        roots = [*POLICY, "scripts", ".agents/ruff.toml", ".agents/secret-exceptions.json", ".github/workflows"]
        # Lint/analysis may also name Python files outside scripts/.
        roots.extend(item for item in check.argv if item.endswith(".py") and not Path(item).is_absolute())
        selected_tools = {key: value for key, value in tools.items()
                          if key not in {"swift", "swiftlint", "node", "bash"} and "node_modules" not in key}
    else:
        # Node's ignored dependency graph, adapters consuming compiler logs, and custom
        # recipes have no complete dependency declaration. Execute them again.
        return None
    try:
        source = dependency_snapshot(root, roots)
    except (OSError, ValueError):
        # External/symlinked dependency roots cannot prove an unchanged input graph.
        return None
    payload = {"schema": 1, "contract": contract(check), "source": source,
               "tools": selected_tools, "environment": {key: os.environ.get(key) for key in ENVIRONMENT}}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def cached_result(root, check, key, directory):
    if key is None:
        return None
    path = Path(root) / ".artifacts/contribution/check-cache" / (key + ".json")
    try:
        cached = json.loads(path.read_text(encoding="utf-8"))
        result = cached["result"]
        if cached["contract"] != contract(check) or cached["fingerprint"] != key or result["status"] != "passed":
            return None
        log = Path(result["log"])
        if hashlib.sha256(log.read_bytes()).hexdigest() != result["log_sha256"]:
            return None
        target = directory / (check.name + ".log")
        if log.resolve() != target.resolve():
            shutil.copyfile(log, target)
        return {**result, "command": check.argv, "cwd": check.cwd, "log": str(target),
                "reused": True, "reused_from": str(log), "input_fingerprint": key}
    except (OSError, ValueError, KeyError, TypeError):
        return None


def retain_result(root, check, key, result):
    if key is not None and result["status"] == "passed":
        write_json(Path(root) / ".artifacts/contribution/check-cache" / (key + ".json"),
                   {"fingerprint": key, "contract": contract(check), "result": result})
