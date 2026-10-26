#!/usr/bin/env bash
set -euo pipefail
for command in curl python3; do
  command -v "$command" > /dev/null || { echo "CI smoke dependency missing: $command" >&2; exit 1; }
done
root="$(cd "${1:?usage: test-release.sh PACKAGE_ROOT EXPECTED_VERSION}" && pwd)"
version="${2:?expected release version required}"
executable="$root/bin/sloppy"
actual="$("$executable" --version)"
[[ "$actual" == "sloppy $version" ]] || { echo "Unexpected version: $actual" >&2; exit 1; }
temporary="$(mktemp -d)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$temporary"
}
trap cleanup EXIT
port="$(python3 - "$temporary" <<'PYTHON'
import json, socket, sys
from pathlib import Path
with socket.socket() as dashboard:
    dashboard.bind(('127.0.0.1', 25102))
with socket.socket() as api:
    api.bind(('127.0.0.1', 0))
    port = api.getsockname()[1]
root = Path(sys.argv[1])
config = {
    'listen': {'host': '127.0.0.1', 'port': port},
    'workspace': {'basePath': str(root), 'name': 'workspace'},
    'auth': {'token': ''}, 'models': [], 'plugins': [], 'gateways': [],
    'nodes': ['local'], 'memory': {'backend': 'sqlite-local-vectors'},
    'sqlitePath': 'core.sqlite',
}
(root / 'config.json').write_text(json.dumps(config))
print(port)
PYTHON
)"
CORE_DASHBOARD_PATH="$root/share/sloppy/dashboard" "$executable" run --config-path "$temporary/config.json" > "$temporary/server.log" 2>&1 &
server_pid=$!
healthy=0
for attempt in {1..60}; do
  if curl -fsS "http://127.0.0.1:$port/health" > /dev/null 2>&1; then healthy=1; break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 0.5
done
if [[ "$healthy" != 1 ]] || ! curl -fsS http://127.0.0.1:25102/ | grep -qi '<html'; then
  tail -100 "$temporary/server.log" >&2
  exit 1
fi
printf '%s\n' "Packaged Sloppy $version: CLI, SQLite, API health and Dashboard passed."
