"""Choose validation scopes from repository-relative changed paths."""

import fnmatch
import json
import importlib.util
from pathlib import Path
import sys

from .execution import Check


def is_documentation_path(path):
    return path.endswith(".md") or ".docc/" in path


def select_profiles(paths, config=None):
    """Return the validation profiles required by a change."""
    if config is None:
        config = json.loads((Path(__file__).resolve().parents[2] / ".agents/validation.json").read_text())
    return {"common"} | {
        name for name, profile in config["profiles"].items()
        if any(fnmatch.fnmatchcase(path, pattern) and
               (not is_documentation_path(path) or name in ("documentation", "docs"))
               for path in paths for pattern in profile["paths"])
    }


def python_suites(root, paths, config):
    suites = set()
    for name in paths:
        if not name.endswith(".py"):
            continue
        mapped = [suite for pattern, values in config["python_suites"].items()
                  if fnmatch.fnmatchcase(name, pattern) for suite in values]
        if mapped:
            suites.update(mapped)
            continue
        path = Path(name)
        if path.name.startswith("test_"):
            suites.add(name)
        else:
            candidate = path.with_name("test_" + path.name)
            if (root / candidate).exists():
                suites.add(candidate.as_posix())
            elif (root / path.parent).exists():
                suites.update(p.relative_to(root).as_posix() for p in (root / path.parent).glob("test_*.py"))
    return sorted(suites)


def swift_inputs(root, paths, config):
    if ".swiftlint.yml" in paths:
        selected = []
        for directory in config["owned_swift_roots"]:
            selected.extend(p.relative_to(root).as_posix() for p in (root / directory).rglob("*.swift")
                            if not any(part in (".build", "Vendor", "node_modules", ".swiftpm") for part in p.parts))
        return sorted(set(selected))
    return [p for p in paths if p.endswith(".swift") and (root / p).is_file()]


def build_checks(root, paths, config, paths_file, logs, quick=False, runtime=None, platform_command=None,
                 dependency_command=None):
    runtime_requested = runtime is not None
    recipes = config.get("commands", {})
    for recipe in recipes.values():
        if recipe is not None and (not isinstance(recipe, list) or not recipe or
                                   not all(isinstance(value, str) and value for value in recipe)):
            raise ValueError("Configured commands must be nonempty JSON argv arrays")
    runtime = runtime or recipes.get("runtime")
    platform_command = platform_command or recipes.get("platform")
    dependency_command = dependency_command or recipes.get("dependency")
    profiles = select_profiles(paths, config)
    timeout = config["timeout_seconds"]
    python = sys.executable
    entry = str(root / "scripts/check_contribution.py")

    def adapter(name, category, action=None, extra=None):
        return Check(name, category, [python, entry, "adapter", action or name, "--files-from", str(paths_file),
                                     "--logs", str(logs), *(extra or [])], timeout=timeout)

    def module(name, category, module_name, arguments):
        if importlib.util.find_spec(module_name) is None:
            return Check(name, category, status="blocked", reason="Missing Python tool: " + module_name)
        return Check(name, category, [python, "-m", module_name, *arguments], timeout=timeout)

    checks = [Check("git-diff", "style", ["git", "diff", "--check", "--no-ext-diff", "HEAD", "--", *paths]),
              adapter("content", "style"), adapter("secrets", "security")]
    python_paths = [p for p in paths if p.endswith(".py") and (root / p).is_file()]
    if "workflow" in profiles:
        python_paths = sorted(set(python_paths) | {p.relative_to(root).as_posix()
                              for p in (root / "scripts/contribution").glob("*.py")}
                              | {"scripts/check_contribution.py", "scripts/test_contribution.py"})
    if "python" in profiles or "workflow" in profiles:
        if python_paths:
            checks.append(module("python-lint", "style", "ruff", ["check", "--config", ".agents/ruff.toml", *python_paths]))
            checks.append(module("python-analysis", "analysis", "bandit",
                                 ["--severity-level", "medium", "--confidence-level", "medium", "-f", "json", *python_paths]))
        if not quick:
            suites = python_suites(root, python_paths, config)
            if "workflow" in profiles:
                suites = sorted(set(suites) | {"scripts/test_contribution.py"})
            if not suites:
                checks.append(Check("python-tests", "tests", status="blocked", reason="No owning Python suite configured"))
            for number, suite in enumerate(suites):
                argv = [python, "-m", "unittest", "discover", "-s", suite] if (root / suite).is_dir() else [
                    python, "-m", "unittest", "discover", "-s", str(Path(suite).parent), "-p", Path(suite).name]
                checks.append(Check("python-tests-" + str(number), "tests", argv, tests=True, timeout=timeout))
    swift_paths = swift_inputs(root, paths, config)
    if "swift" in profiles:
        checks.append(adapter("swift-lint", "style") if swift_paths else
                      Check("swift-lint", "style", status="not_applicable", reason="No existing Swift source changed"))
        if not quick:
            common = ["--scratch-path", config["swift_scratch"]]
            checks.append(Check("swift-build", "analysis", ["swift", "build", "--build-tests", "-v", *common], timeout=timeout))
            checks.append(adapter("swift-analysis", "analysis") if swift_paths else
                          Check("swift-analysis", "analysis", status="not_applicable", reason="No existing Swift source changed"))
            for product, name in (("sloppy", "sloppy-release"), ("SloppyNode", "node-release")):
                checks.append(Check(name, "analysis", ["swift", "build", "-c", "release", "--product", product, *common], timeout=timeout))
            checks.append(Check("swift-tests", "tests", ["swift", "test", "--parallel", *common], tests=True, timeout=timeout))
    if "swift" in profiles and not quick:
        packages = set(config.get("swift_packages", {})) if ".swiftlint.yml" in paths else {
            Path(name).parts[1] for name in paths if name.startswith("Packages/") and len(Path(name).parts) > 2}
        for package in sorted(packages):
            policy = config.get("swift_packages", {}).get(package)
            if policy is None:
                checks.append(Check("package-tests-" + package, "tests", status="blocked", reason="Configure owning package validation"))
                continue
            tests = policy["tests"]
            checks.append(Check("package-build-" + package, "analysis",
                                ["swift", "build", "--build-tests", "-v", "--package-path", "Packages/" + package,
                                 "--scratch-path", config["swift_scratch"] + "-" + package], timeout=timeout))
            if any(p.startswith("Packages/" + package + "/") for p in swift_paths):
                checks.append(adapter("package-analysis-" + package, "analysis", "package-analysis", ["--package", package]))
            if not tests:
                continue
            checks.append(Check("package-tests-" + package, "tests",
                                ["swift", "test" if tests else "build", "--package-path", "Packages/" + package,
                                 "--scratch-path", config["swift_scratch"] + "-" + package], tests=tests, timeout=timeout))
    if "client" in profiles:
        selected_client = [p for p in swift_paths if p.startswith("Apps/Client/")]
        if selected_client:
            checks.append(adapter("client-lint", "style"))
    if "client" in profiles and not quick:
        common = ["--package-path", "Apps/Client", "--scratch-path", config["swift_scratch"] + "-client"]
        native = sys.platform == "darwin"
        for name, argv, tests in (("client-build", ["swift", "build", "--build-tests", "-v", *common], False),
                                  ("client-tests", ["swift", "test", *common], True)):
            checks.append(Check(name, "platform", argv, tests=tests, timeout=timeout,
                                status="" if native else "blocked", reason="" if native else "Apple client requires macOS with Xcode"))
        if selected_client:
            checks.append(adapter("client-analysis", "analysis") if native else
                          Check("client-analysis", "analysis", status="blocked", reason="Apple analysis requires macOS with Xcode"))
    if "native_client" in profiles:
        selected_native = [p for p in swift_paths if p.startswith("ClientNative/")]
        if selected_native:
            checks.append(adapter("native-lint", "style"))
        if not quick:
            common = ["--package-path", "ClientNative", "--scratch-path", config["swift_scratch"] + "-native"]
            native = sys.platform == "darwin"
            for name, argv, tests in (("native-build", ["swift", "build", "--build-tests", "-v", *common], False),
                                      ("native-tests", ["swift", "test", *common], True)):
                checks.append(Check(name, "platform", argv, tests=tests, timeout=timeout,
                                    status="" if native else "blocked", reason="" if native else "Native client requires macOS 26 with Xcode"))
            if selected_native:
                checks.append(adapter("native-analysis", "analysis") if native else
                              Check("native-analysis", "analysis", status="blocked", reason="Native analysis requires macOS 26 with Xcode"))
    if "dashboard" in profiles and not quick:
        for name, argv, tests in (
            ("dashboard-typecheck", ["node", "node_modules/typescript/bin/tsc", "--noEmit"], False),
            ("dashboard-build", ["node", "node_modules/vite/bin/vite.js", "build"], False),
            ("dashboard-tests", ["node", "--test", *sorted(p.relative_to(root / "Dashboard").as_posix()
                for p in (root / "Dashboard/scripts").glob("*Test.mjs"))], True),
        ):
            checks.append(Check(name, "tests" if tests else "analysis", argv, cwd="Dashboard", tests=tests, timeout=timeout))
    if "docs" in profiles and not quick:
        checks.append(Check("docs-build", "documentation", ["node", "node_modules/vitepress/bin/vitepress.js", "build", "."], cwd="docs", timeout=timeout))
    runtime_needed = any(not is_documentation_path(p) and fnmatch.fnmatchcase(p, pattern)
                         for p in paths for pattern in config["runtime_paths"])
    if not quick and (runtime_needed or runtime_requested):
        checks.append(Check("runtime-smoke", "dynamic", runtime or [], timeout=timeout,
                            status="" if runtime else "blocked", reason="" if runtime else "Provide a real runtime smoke command for this change"))
    if not quick and "platform" in profiles:
        checks.append(Check("platform-matrix", "platform", platform_command or [], timeout=timeout,
                            status="" if platform_command else "blocked",
                            reason="" if platform_command else "Provide the required platform validation command or use its CI runner"))
    if not quick and any(fnmatch.fnmatchcase(p, pattern) for p in paths for pattern in config["dependency_paths"]):
        if dependency_command:
            checks.append(Check("dependency-review", "security", dependency_command, timeout=timeout))
        elif all(p == "scripts/contribution-requirements.txt" or not any(fnmatch.fnmatchcase(p, pattern)
                 for pattern in config["dependency_paths"]) for p in paths):
            checks.append(module("dependency-review", "security", "pip_audit",
                                 ["-r", "scripts/contribution-requirements.txt", "--progress-spinner", "off"]))
        else:
            checks.append(Check("dependency-review", "security", status="blocked",
                                reason="Provide advisory analysis for the changed dependency manifests"))
    for category in ("style", "analysis", "tests", "dynamic", "platform", "security"):
        if not any(check.category == category for check in checks):
            checks.append(Check(category + "-not-applicable", category, status="not_applicable",
                                reason="No changed paths require this category in the selected profile"))
    return checks
