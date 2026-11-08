"""Read Git state without changing the index or the worktree."""

import hashlib
import json
import os
from pathlib import Path
import subprocess

from .execution import _stop


def git(root, *args):
    command = ["git", "-c", "core.fsmonitor=false", "-C", str(root), *args]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=os.name != "nt")
    try:
        output, errors = process.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        _stop(process)
        process.communicate()
        raise
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, command, output, errors)
    return output.decode("utf-8", errors="surrogateescape")



def safe_path(root, name):
    root = Path(root).resolve()
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or not relative.parts or relative.parts[0] == ".git":
        raise ValueError("Expected a repository-relative path: " + str(name))
    path = root / relative
    if not path.resolve().is_relative_to(root):
        raise ValueError("Path leaves the repository: " + str(name))
    return path


def changed_files(root, base="HEAD", staged=False):
    args = ["diff", "--no-renames", "--name-only", "-z", "--diff-filter=ACDMRTUXB"]
    args += ["--cached"] if staged else [base]
    paths = set(git(root, *args).split("\0")) - {""}
    if not staged:
        paths.update(filter(None, git(root, "ls-files", "--others", "--exclude-standard", "-z").split("\0")))
    return sorted(paths)


def staged_files(root):
    paths = changed_files(root, staged=True)
    unstaged = set(filter(None, git(root, "diff", "--name-only", "-z").split("\0")))
    if unstaged.intersection(paths):
        raise ValueError("Partially staged files: stage the complete files or validate an index snapshot")
    # Other dirty code could change test behavior; never claim that a dirty worktree proves a commit.
    if unstaged:
        raise ValueError("Unstaged tracked changes: validate a clean staged worktree before committing")
    return paths


def snapshot(root):
    """Fingerprint index blobs plus dirty/new contents, including deletions and selected environment."""
    digest = hashlib.sha256()
    digest.update(git(root, "rev-parse", "HEAD").encode())
    digest.update(git(root, "ls-files", "--stage", "-z").encode("utf-8", errors="surrogateescape"))
    dirty = set(filter(None, git(root, "ls-files", "--modified", "--others", "--exclude-standard", "-z").split("\0")))
    for name in sorted(dirty):
        path = safe_path(root, name)
        digest.update(name.encode("utf-8", errors="surrogateescape"))
        digest.update(b"\0")
        if path.is_file():
            digest.update(hashlib.sha256(path.read_bytes()).digest())
        else:
            digest.update(b"<missing>")
    modules = Path(root) / ".gitmodules"
    if modules.is_file():
        entries = git(root, "config", "--file", str(modules), "--get-regexp", r"^submodule\..*\.path$")
        for entry in entries.splitlines():
            name = entry.split(None, 1)[1]
            dependency = safe_path(root, name)
            if (dependency / ".git").exists():
                digest.update(name.encode())
                digest.update(snapshot(dependency).encode())
            else:
                digest.update((name + ":uninitialized").encode())
    environment = {key: os.environ.get(key) for key in (
        "ADAENGINE_HEADLESS", "ADAENGINE_DISABLE_SWAN", "ADAENGINE_LOCAL", "DEVELOPER_DIR",
        "SDKROOT", "SWIFT_EXEC", "SLOPPY_CONFIG_PATH", "NODE_ENV", "CI",
    )}
    digest.update(json.dumps(environment, sort_keys=True).encode())
    return digest.hexdigest()


def document_hash(root, name):
    return hashlib.sha256(safe_path(root, name).read_bytes()).hexdigest()


def dependency_snapshot(root, roots):
    """Hash declared source trees, including new/deleted files and dirty submodules."""
    root = Path(root).resolve()
    digest = hashlib.sha256()
    names = set(filter(None, git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z").split("\0")))
    generated = {".git", ".build", ".artifacts", "node_modules", "__pycache__"}
    for name in roots:
        path = safe_path(root, name)
        if path.is_dir():
            for directory, children, files in os.walk(path, followlinks=False):
                children[:] = [child for child in children if child not in generated]
                names.update((Path(directory) / filename).relative_to(root).as_posix() for filename in files)
    for name in sorted(names):
        if not any(name == prefix or name.startswith(prefix.rstrip("/") + "/") for prefix in roots):
            continue
        path = safe_path(root, name)
        digest.update(name.encode("utf-8", errors="surrogateescape"))
        if path.is_dir() and (path / ".git").exists():
            digest.update(snapshot(path).encode())
        else:
            digest.update(hashlib.sha256(path.read_bytes()).digest() if path.is_file() else b"<missing>")
    # Missing declared roots matter too (including ignored configuration inputs).
    for name in sorted(roots):
        path = safe_path(root, name)
        digest.update(name.encode())
        if path.is_file():
            digest.update(hashlib.sha256(path.read_bytes()).digest())
        elif not path.exists():
            digest.update(b"<missing>")
    return digest.hexdigest()
