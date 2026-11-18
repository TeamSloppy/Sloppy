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
from pathlib import Path
import re
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error("--batch-size must be positive")
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
    print(f"Inventory: {len(identifiers)} tests in {len(batches)} isolated batches", flush=True)
    results = []
    for number, batch in enumerate(batches, 1):
        print(f"Batch {number}/{len(batches)}: {len(batch)} tests", flush=True)
        pattern = "|".join(sorted({re.escape(function_name(name)) for name in batch}))
        result = subprocess.run(
            ["swift", "test", "--skip-build", "--no-parallel", "--filter", pattern],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
        )
        print(result.stdout, end="", flush=True)
        counts = re.findall(r"Test run with (\d+) tests?\b", result.stdout)
        observed = int(counts[-1]) if counts else None
        passed = result.returncode == 0 and observed == len(batch)
        results.append({
            "batch": number, "tests": batch, "expected": len(batch),
            "observed": observed, "exitCode": result.returncode, "passed": passed,
        })
        Path("swift-test-batches.json").write_text(json.dumps(results, indent=2) + "\n")
        if not passed:
            print(f"Batch {number} failed: expected {len(batch)} tests, observed {observed}, "
                  f"exit {result.returncode}", flush=True)
    failed = [result["batch"] for result in results if not result["passed"]]
    observed = sum(result["observed"] or 0 for result in results)
    print(f"Swift Testing: {observed}/{len(identifiers)} tests; failed batches: {failed}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
