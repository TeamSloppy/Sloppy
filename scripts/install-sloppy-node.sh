#!/usr/bin/env bash

set -euo pipefail

RELEASE_REPO="${SLOPPY_RELEASE_REPO:-TeamSloppy/Sloppy}"
RELEASE_TAG="${SLOPPY_RELEASE_TAG:-}"
BIN_DIR="${SLOPPY_BIN_DIR:-$HOME/.local/bin}"
INSTALL_ROOT="${SLOPPY_NODE_INSTALL_ROOT:-$HOME/.local/share/sloppy-node}"
DRY_RUN="${SLOPPY_DRY_RUN:-0}"

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: install-sloppy-node.sh [options]

Install the standalone sloppy-node executor from GitHub Release assets.

Options:
  --release-tag <t>   Use this tag (for example v1.2.3). Default: latest release.
  --bin-dir <path>    Install command symlink into <path>. Default: $BIN_DIR
  --install-root <p>  Extract release files into <p>. Default: $INSTALL_ROOT
  --dry-run           Print actions without executing them.
  --help, -h          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-tag) RELEASE_TAG="${2:-}"; shift 2 ;;
    --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
    --install-root) INSTALL_ROOT="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

command_exists curl || die "curl is required."
command_exists tar || die "tar is required."
if command_exists shasum; then
  sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command_exists sha256sum; then
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
else
  die "shasum or sha256sum is required."
fi

if [[ -z "$RELEASE_TAG" ]]; then
  command_exists python3 || die "python3 is required to resolve the latest release. Pass --release-tag to skip lookup."
  RELEASE_TAG="$(python3 -c 'import json,sys,urllib.request
repo=sys.argv[1]
req=urllib.request.Request("https://api.github.com/repos/"+repo+"/releases/latest", headers={"Accept":"application/vnd.github+json","User-Agent":"install-sloppy-node.sh"})
print(json.load(urllib.request.urlopen(req))["tag_name"])
' "$RELEASE_REPO")"
fi

arch="$(uname -m)"
case "$(uname -s):$arch" in
  Darwin:arm64) asset="SloppyNode-macos-arm64.tar.gz" ;;
  Darwin:x86_64) asset="SloppyNode-macos-x86_64.tar.gz" ;;
  *) die "Standalone sloppy-node release assets are currently supported on macOS. Use Windows PowerShell installer on Windows." ;;
esac

sums_url="https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/SHA256SUMS.txt"
asset_url="https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${asset}"

log "Installing sloppy-node from $RELEASE_REPO @ $RELEASE_TAG ($asset)"
if [[ "$DRY_RUN" == "1" ]]; then
  log "Would download $sums_url"
  log "Would download $asset_url"
  log "Would extract into $INSTALL_ROOT and link $BIN_DIR/sloppy-node"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -H "Accept: application/octet-stream" -H "User-Agent: install-sloppy-node.sh" -o "$tmp/SHA256SUMS.txt" "$sums_url"
curl -fsSL -H "Accept: application/octet-stream" -H "User-Agent: install-sloppy-node.sh" -o "$tmp/$asset" "$asset_url"
expected="$(awk -v n="$asset" '$2 == n { print $1; exit }' "$tmp/SHA256SUMS.txt")"
actual="$(sha256_file "$tmp/$asset")"
[[ -n "$expected" ]] || die "Checksum file did not include $asset."
[[ "$expected" == "$actual" ]] || die "SHA256 mismatch for $asset."

mkdir -p "$INSTALL_ROOT" "$BIN_DIR"
tar -C "$INSTALL_ROOT" -xzf "$tmp/$asset"
ln -sf "$INSTALL_ROOT/bin/sloppy-node" "$BIN_DIR/sloppy-node"

log "Install complete."
log "  Binary: $BIN_DIR/sloppy-node"
log "  Verify: printf '{\"action\":\"status\",\"payload\":{}}' | sloppy-node invoke --stdin"
