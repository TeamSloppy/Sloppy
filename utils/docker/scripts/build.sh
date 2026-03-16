#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

if [[ -n "${CONTAINER_CLI:-}" ]]; then
  container_cli=("$CONTAINER_CLI")
elif command -v docker >/dev/null 2>&1; then
  container_cli=("docker")
elif command -v podman >/dev/null 2>&1; then
  container_cli=("podman")
else
  echo "Neither docker nor podman is available. Set CONTAINER_CLI to override." >&2
  exit 1
fi

"${container_cli[@]}" compose -f utils/docker/docker-compose.yml build "$@"
