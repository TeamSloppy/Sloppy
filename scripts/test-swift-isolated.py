#!/usr/bin/env python3
"""Run the complete SwiftPM test inventory in fresh, bounded processes.

Stable Linux Foundation versions can over-read readdir's buffer in Process.run
once a long-lived test process accumulates many descriptors. Keep all tests,
but isolate their process state until the upstream fix ships in the toolchain:
https://github.com/swiftlang/swift-corelibs-foundation/pull/5472
"""

import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys


def function_name(identifier):
    return identifier.rsplit("/", 1)[-1].rsplit(".", 1)[-1].split("(", 1)[0]


def batches_for(identifiers, limit):
    # SwiftPM's listing and Swift Testing's internal qualified IDs use different
    # separators. Function-name filters work in both. Keep substring collisions
    # together so a broad name can never run another batch's tests a second time.
    parents = list(range(len(identifiers)))

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for name in {function_name(identifier) for identifier in identifiers}:
        matches = [i for i, identifier in enumerate(identifiers) if name in identifier]
        for index in matches[1:]:
            parents[root(index)] = root(matches[0])

    components = defaultdict(list)
    for index, identifier in enumerate(identifiers):
        components[root(index)].append(identifier)

    batches, current = [], []
    for component in components.values():
        if len(component) > limit:
            raise ValueError(f"Filter collision group exceeds batch limit: {component}")
        if len(current) + len(component) > limit:
            batches.append(current)
            current = []
        current.extend(component)
    if current:
        batches.append(current)

    for batch in batches:
        pattern = "|".join(sorted({re.escape(function_name(name)) for name in batch}))
        matched = {name for name in identifiers if re.search(pattern, name)}
        if matched != set(batch):
            raise ValueError("Test filters overlap or omit an inventory entry")
    return batches


def native_runner():
    environment = os.environ.copy()
    output = subprocess.run(["swift", "build", "--show-bin-path"], check=True,
                            stdout=subprocess.PIPE, text=True).stdout
    products = list(Path(output.strip().splitlines()[-1]).glob("*.xctest"))
    if len(products) != 1:
        raise ValueError(f"Expected one test product, found {products}")
    binary = products[0]
    if sys.platform == "darwin":
        binary = binary / "Contents" / "MacOS" / binary.stem
        target = subprocess.run(["swift", "-print-target-info"], check=True,
                                stdout=subprocess.PIPE, text=True)
        resources = Path(json.loads(target.stdout)["paths"]["runtimeResourcePath"])
        helper = resources.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
        platform = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
                                  check=True, stdout=subprocess.PIPE, text=True).stdout.strip()
        frameworks = str(Path(platform) / "Developer/Library/Frameworks")
        previous = environment.get("DYLD_FRAMEWORK_PATH")
        environment["DYLD_FRAMEWORK_PATH"] = frameworks + (":" + previous if previous else "")
        return [str(helper), "--test-bundle-path", str(binary)], environment
    if sys.platform != "linux":
        raise ValueError("This runner supports Linux CI and local macOS verification")
    return [str(binary)], environment


def run_batch(command, log_path, timeout, environment):
    timed_out = False
    with log_path.open("w") as output:
        with subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                              start_new_session=True, env=environment) as process:
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                # Own only this test process group, never another build or app.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                code = process.wait()
    text = log_path.read_text(errors="replace")
    print(text, end="", flush=True)
    return code, text, timed_out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--batch-timeout", type=float, default=180)
    args = parser.parse_args()
    if args.batch_size < 1 or args.batch_timeout <= 0:
        parser.error("Batch size and timeout must be positive")
    if not args.skip_build:
        subprocess.run(["swift", "build", "--build-tests"], check=True)
    listing = subprocess.run(
        ["swift", "test", "list", "--skip-build"], check=True,
        stdout=subprocess.PIPE, text=True,
    ).stdout
    identifiers = [line.strip() for line in listing.splitlines() if line.strip()]
    if not identifiers or len(set(identifiers)) != len(identifiers):
        raise ValueError("SwiftPM returned an empty or duplicate test inventory")
    Path("swift-test-inventory.txt").write_text(listing)
    batches = batches_for(identifiers, args.batch_size)
    runner, environment = native_runner()
    runner += ["--testing-library", "swift-testing", "--no-parallel"]
    logs = Path("swift-test-batch-logs")
    logs.mkdir(exist_ok=True)
    print(f"Inventory: {len(identifiers)} tests in {len(batches)} isolated batches", flush=True)
    results = []
    Path("swift-test-batches.json").write_text("[]\n")
    for number, batch in enumerate(batches, 1):
        print(f"Batch {number}/{len(batches)}: {len(batch)} tests", flush=True)
        pattern = "|".join(sorted({re.escape(function_name(name)) for name in batch}))
        code, output, timed_out = run_batch(
            runner + ["--filter", pattern], logs / f"{number:03d}.log", args.batch_timeout, environment,
        )
        counts = re.findall(r"Test run with (\d+) tests?\b", output)
        observed = int(counts[-1]) if counts else None
        passed = not timed_out and code == 0 and observed == len(batch)
        results.append({
            "batch": number, "tests": batch, "expected": len(batch),
            "observed": observed, "exitCode": code, "passed": passed, "timedOut": timed_out,
        })
        Path("swift-test-batches.json").write_text(json.dumps(results, indent=2) + "\n")
        if not passed:
            print(f"Batch {number} failed: expected {len(batch)} tests, observed {observed}, "
                  f"exit {code}, timeout {timed_out}", flush=True)
    failed = [result["batch"] for result in results if not result["passed"]]
    observed = sum(result["observed"] or 0 for result in results)
    print(f"Swift Testing: {observed}/{len(identifiers)} tests; failed batches: {failed}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
