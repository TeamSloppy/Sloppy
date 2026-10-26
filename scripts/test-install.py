#!/usr/bin/env python3
"""Offline installer acceptance tests. Never modifies the user's installation."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


INSTALLER = Path(__file__).with_name("install.sh").resolve()


class ReleaseInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sloppy-install-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.installation = self.root / "installed Sloppy"
        self.profile = self.root / "shell"
        self.profile.mkdir()
        self.env = {
            **os.environ,
            "PATH": f"{self.tools}:/usr/bin:/bin",
            "SHELL": "/bin/zsh",
            "ZDOTDIR": str(self.profile),
            "SLOPPY_LOCAL_ROOT": str(self.installation),
            "SLOPPY_BIN_DIR": str(self.installation / "bin"),
            "SLOPPY_DASHBOARD_DIR": str(self.installation / "share/sloppy/dashboard"),
            "SLOPPY_TEST_ROOT": str(self.root),
            "SLOPPY_TEST_KERNEL": "Darwin",
            "SLOPPY_TEST_ARCH": "arm64",
        }
        for key in list(self.env):
            if key.startswith("SLOPPY_") and key not in {
                "SLOPPY_LOCAL_ROOT", "SLOPPY_BIN_DIR", "SLOPPY_DASHBOARD_DIR",
                "SLOPPY_TEST_ROOT", "SLOPPY_TEST_KERNEL", "SLOPPY_TEST_ARCH",
            }:
                del self.env[key]
        self.write_executable(self.tools / "uname", '#!/bin/sh\ncase "$1" in -s) echo "$SLOPPY_TEST_KERNEL";; -m) echo "$SLOPPY_TEST_ARCH";; esac\n')
        self.write_executable(self.tools / "curl", '''#!/bin/bash
set -eu
[[ "${SLOPPY_TEST_NETWORK_FAIL:-0}" != 1 ]] || exit 22
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output="$2"; shift 2;;
    -w) shift 2;;
    -H) shift 2;;
    -*) shift;;
    *) url="$1"; shift;;
  esac
done
case "$url" in
  */releases/latest) printf '%s' 'https://github.com/TeamSloppy/Sloppy/releases/tag/v9.9.9';;
  */SHA256SUMS.txt) cp "$SLOPPY_TEST_ROOT/SHA256SUMS.txt" "$output";;
  *) cp "$SLOPPY_TEST_ROOT/${url##*/}" "$output";;
esac
''')
        for tool in ("swift", "git", "node", "npm", "python3", "jq"):
            self.write_executable(self.tools / tool, f'#!/bin/sh\necho "Unexpected dependency: {tool}" >&2\nexit 99\n')
        self.make_archive()

    def write_executable(self, path, contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        path.chmod(0o755)

    def make_archive(self, name="Sloppy-macos-arm64.tar.gz", valid=True, runnable=True):
        payload = self.root / "payload"
        self.write_executable(payload / "bin/sloppy", '#!/bin/sh\necho "Sloppy fixture 9.9.9"\n' + ("exit 0\n" if runnable else "exit 1\n"))
        dashboard = payload / "share/sloppy/dashboard/dist"
        dashboard.mkdir(parents=True, exist_ok=True)
        (dashboard / "index.html").write_text("Sloppy dashboard fixture")
        (dashboard.parent / "config.json").write_text("{}")
        archive = self.root / name
        with tarfile.open(archive, "w:gz") as output:
            output.add(payload / "bin", arcname="bin")
            if valid:
                output.add(payload / "share", arcname="share")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.root / "SHA256SUMS.txt").write_text(f"{digest}  {name}\n")

    def run_installer(self, *args, succeeds=True):
        result = subprocess.run(["/bin/bash", str(INSTALLER), *args], env=self.env,
                                text=True, input="", capture_output=True, timeout=15)
        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
        return result

    def test_default_installs_latest_without_build_tools_and_reinstall_is_safe(self):
        self.run_installer()
        self.run_installer()
        self.assertFalse((self.installation / "bin/sloppy").is_symlink())
        self.assertEqual(os.readlink(self.installation / "bin/slop"), str(self.installation / "bin/sloppy"))
        self.assertEqual((self.profile / ".zshrc").read_text().count("# Sloppy CLI"), 1)
        # The generated profile handles spaces and makes the CLI immediately resolvable.
        result = subprocess.run(["/bin/bash", "-c", '. "$ZDOTDIR/.zshrc"; sloppy --version'],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("9.9.9", result.stdout)

    def test_checksum_failure_preserves_existing_installation(self):
        self.run_installer()
        (self.root / "SHA256SUMS.txt").write_text("0" * 64 + "  Sloppy-macos-arm64.tar.gz\n")
        result = self.run_installer(succeeds=False)
        self.assertIn("SHA256 mismatch", result.stderr)
        self.assertTrue((self.installation / "bin/sloppy").is_file())

    def test_incomplete_or_unrunnable_archive_does_not_install(self):
        for valid, runnable in ((False, True), (True, False)):
            with self.subTest(valid=valid, runnable=runnable):
                self.make_archive(valid=valid, runnable=runnable)
                self.run_installer(succeeds=False)
                self.assertFalse(self.installation.exists())

    def test_source_symlink_is_replaced_without_overwriting_its_target(self):
        old_build = self.root / "old-checkout-build"
        old_build.write_text("keep the source build")
        (self.installation / "bin").mkdir(parents=True)
        (self.installation / "bin/sloppy").symlink_to(old_build)
        self.run_installer("--no-path")
        self.assertEqual(old_build.read_text(), "keep the source build")
        self.assertFalse((self.installation / "bin/sloppy").is_symlink())

    def test_linux_release_and_no_path_option(self):
        self.env.update(SLOPPY_TEST_KERNEL="Linux", SLOPPY_TEST_ARCH="x86_64")
        self.make_archive("Sloppy-linux-x86_64.tar.gz")
        self.run_installer("--no-path")
        self.assertFalse((self.profile / ".zshrc").exists())

    def test_unsupported_platform_and_failed_download_leave_no_installation(self):
        self.env["SLOPPY_TEST_ARCH"] = "riscv64"
        self.run_installer(succeeds=False)
        self.env["SLOPPY_TEST_ARCH"] = "arm64"
        self.env["SLOPPY_TEST_NETWORK_FAIL"] = "1"
        self.run_installer(succeeds=False)
        self.assertFalse(self.installation.exists())


if __name__ == "__main__":
    unittest.main()
