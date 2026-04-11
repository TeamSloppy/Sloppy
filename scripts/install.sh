#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
REPO_URL="${SLOPPY_REPO_URL:-https://github.com/TeamSloppy/Sloppy.git}"
RELEASE_REPO="${SLOPPY_RELEASE_REPO:-TeamSloppy/Sloppy}"
RELEASE_TAG="${SLOPPY_RELEASE_TAG:-}"
INSTALL_DIR="${SLOPPY_INSTALL_DIR:-$HOME/.local/share/sloppy/source}"
BIN_DIR="${SLOPPY_BIN_DIR:-$HOME/.local/bin}"
DASHBOARD_DIR="${SLOPPY_DASHBOARD_DIR:-$HOME/.local/share/sloppy/dashboard}"
LOCAL_ROOT="${SLOPPY_LOCAL_ROOT:-$HOME/.local}"
MODE="${SLOPPY_INSTALL_MODE:-}"
INSTALL_DIR_SET=0
NO_PROMPT="${SLOPPY_NO_PROMPT:-0}"
DRY_RUN="${SLOPPY_DRY_RUN:-0}"
VERBOSE="${SLOPPY_VERBOSE:-0}"
NO_LINK="${SLOPPY_NO_LINK:-0}"
NO_GIT_UPDATE="${SLOPPY_NO_GIT_UPDATE:-0}"

if [[ -n "${SLOPPY_INSTALL_DIR+x}" ]]; then
  INSTALL_DIR_SET=1
fi

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

debug() {
  if [[ "$VERBOSE" == "1" ]]; then
    printf 'debug: %s\n' "$*" >&2
  fi
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Install Sloppy from source and optionally build the Dashboard bundle, or install
prebuilt binaries from a GitHub Release.

Options:
  --release           Install sloppy and SloppyNode from GitHub Release assets (no Swift build).
  --release-tag <t>   Use this tag (for example v1.2.3). Default: latest release.
  --bundle            Build the server stack and Dashboard bundle.
  --server-only       Build only the server stack.
  --dir <path>        Clone or update the Sloppy checkout in <path> when not running inside a checkout.
  --bin-dir <path>    Install command symlinks into <path>. Default: $BIN_DIR
  --dashboard-dir <path>
                     Install the built Dashboard bundle into <path>. Default: $DASHBOARD_DIR
  --no-link           Do not create symlinks for sloppy and SloppyNode.
  --no-git-update     Do not pull an existing checkout before building.
  --no-prompt         Disable interactive prompts and use defaults.
  --dry-run           Print the actions without executing them.
  --verbose           Enable verbose installer logs.
  --help, -h          Show this help.

Environment variables:
  SLOPPY_INSTALL_MODE=bundle|server|release
  SLOPPY_INSTALL_DIR=/path/to/checkout
  SLOPPY_BIN_DIR=/path/to/bin
  SLOPPY_DASHBOARD_DIR=/path/to/dashboard
  SLOPPY_LOCAL_ROOT=$HOME/.local   (layout root for --release; default ~/.local)
  SLOPPY_RELEASE_REPO=owner/Sloppy  (GitHub repo for release assets)
  SLOPPY_RELEASE_TAG=v1.2.3         (optional; default latest)
  SLOPPY_NO_PROMPT=1
  SLOPPY_DRY_RUN=1
  SLOPPY_VERBOSE=1
  SLOPPY_NO_LINK=1
  SLOPPY_NO_GIT_UPDATE=1
  SLOPPY_REPO_URL=https://github.com/TeamSloppy/Sloppy.git
EOF
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    {
      printf 'dry-run:'
      printf ' %q' "$@"
      printf '\n'
    } >&2
    return 0
  fi
  "$@"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_command() {
  local command_name="$1"
  local install_hint="$2"
  if ! command_exists "$command_name"; then
    die "Required command '$command_name' was not found. $install_hint"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle)
        MODE="bundle"
        shift
        ;;
      --server-only)
        MODE="server"
        shift
        ;;
      --release)
        MODE="release"
        shift
        ;;
      --release-tag)
        [[ $# -ge 2 ]] || die "--release-tag requires a value"
        RELEASE_TAG="$2"
        shift 2
        ;;
      --dir)
        [[ $# -ge 2 ]] || die "--dir requires a value"
        INSTALL_DIR="$2"
        INSTALL_DIR_SET=1
        shift 2
        ;;
      --bin-dir)
        [[ $# -ge 2 ]] || die "--bin-dir requires a value"
        BIN_DIR="$2"
        shift 2
        ;;
      --dashboard-dir)
        [[ $# -ge 2 ]] || die "--dashboard-dir requires a value"
        DASHBOARD_DIR="$2"
        shift 2
        ;;
      --no-link)
        NO_LINK="1"
        shift
        ;;
      --no-git-update)
        NO_GIT_UPDATE="1"
        shift
        ;;
      --no-prompt)
        NO_PROMPT="1"
        shift
        ;;
      --dry-run)
        DRY_RUN="1"
        shift
        ;;
      --verbose)
        VERBOSE="1"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

current_checkout_root() {
  local probe_dir="$PWD"
  if [[ -f "$probe_dir/Package.swift" && -f "$probe_dir/Dashboard/package.json" ]]; then
    printf '%s\n' "$probe_dir"
    return 0
  fi

  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root
    repo_root="$(cd "$script_dir/.." && pwd)"
    if [[ -f "$repo_root/Package.swift" && -f "$repo_root/Dashboard/package.json" ]]; then
      printf '%s\n' "$repo_root"
      return 0
    fi
  fi

  return 1
}

ensure_mode() {
  if [[ -n "$MODE" ]]; then
    case "$MODE" in
      bundle|server|release) return 0 ;;
      *)
        die "Unsupported install mode '$MODE'. Use 'bundle', 'server', or 'release'."
        ;;
    esac
  fi

  if [[ "$NO_PROMPT" == "1" || ! -t 0 ]]; then
    MODE="bundle"
    return 0
  fi

  log "Choose install mode:"
  log "  1) bundle      Build sloppy, SloppyNode, and Dashboard"
  log "  2) server-only Build sloppy and SloppyNode only"
  log "  3) release     Download prebuilt binaries from GitHub Releases"
  printf 'Selection [1]: '
  read -r selection
  case "$selection" in
    ""|1)
      MODE="bundle"
      ;;
    2)
      MODE="server"
      ;;
    3)
      MODE="release"
      ;;
    *)
      die "Invalid selection '$selection'."
      ;;
  esac
}

ensure_prerequisites() {
  if [[ "$MODE" == "release" ]]; then
    require_command curl "Install curl and re-run the installer."
    require_command tar "Install tar and re-run the installer."
    if command_exists shasum; then
      :
    elif command_exists sha256sum; then
      :
    else
      die "Need shasum or sha256sum to verify release checksums."
    fi
    if [[ -z "${RELEASE_TAG:-}" ]]; then
      if ! command_exists python3 && ! command_exists jq; then
        die "Install python3 or jq to resolve the latest release, or set SLOPPY_RELEASE_TAG (or use --release-tag)."
      fi
    fi
    return 0
  fi

  require_command git "Install Git and re-run the installer."
  require_command swift "Install Swift 6 and re-run the installer."

  if [[ "$MODE" == "bundle" ]]; then
    require_command node "Install Node.js and re-run the installer."
    require_command npm "Install npm and re-run the installer."
  fi

  if [[ "$(uname -s)" == "Linux" ]] && command_exists pkg-config; then
    if ! pkg-config --exists sqlite3; then
      warn "SQLite development headers were not detected. If the Swift build fails, install libsqlite3-dev first."
    fi
  fi
}

sha256_file() {
  local f="$1"
  if command_exists shasum; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    sha256sum "$f" | awk '{print $1}'
  fi
}

fetch_latest_release_tag() {
  local repo="$1"
  local json url api_header
  url="https://api.github.com/repos/${repo}/releases/latest"
  api_header=(-H "Accept: application/vnd.github+json" -H "User-Agent: sloppy-install.sh")
  if command_exists python3; then
    python3 -c 'import json,sys,urllib.request
repo=sys.argv[1]
req=urllib.request.Request(
  "https://api.github.com/repos/"+repo+"/releases/latest",
  headers={"Accept":"application/vnd.github+json","User-Agent":"sloppy-install.sh"},
)
print(json.load(urllib.request.urlopen(req))["tag_name"])
' "$repo"
    return 0
  fi
  json="$(curl -fsSL "${api_header[@]}" "$url")" || die "Failed to fetch latest release metadata for $repo."
  if command_exists jq; then
    printf '%s\n' "$(printf '%s\n' "$json" | jq -r .tag_name)"
    return 0
  fi
  printf '%s\n' "$json" | tr ',' '\n' | grep '"tag_name"' | head -1 | sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p'
}

release_tarball_name() {
  local kernel arch
  kernel="$(uname -s)"
  arch="$(uname -m)"
  case "$kernel" in
    Linux)
      case "$arch" in
        x86_64) printf '%s\n' "Sloppy-linux-x86_64.tar.gz" ;;
        *)
          die "No prebuilt release for Linux arch $arch yet. Build from source or use a supported platform."
          ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        arm64) printf '%s\n' "Sloppy-macos-arm64.tar.gz" ;;
        x86_64) printf '%s\n' "Sloppy-macos-x86_64.tar.gz" ;;
        *)
          die "No prebuilt release for macOS arch $arch yet."
          ;;
      esac
      ;;
    *)
      die "Unsupported operating system for --release: $kernel"
      ;;
  esac
}

expected_sha256_from_sums() {
  local name="$1"
  local sumfile="$2"
  awk -v n="$name" '$2 == n { print $1; exit }' "$sumfile"
}

install_from_github_release() {
  local tag tarball sums_url tb_url sums_path tb_path tmp expected actual
  tag="${RELEASE_TAG:-}"
  if [[ -z "$tag" ]]; then
    log "Resolving latest release tag for $RELEASE_REPO"
    tag="$(fetch_latest_release_tag "$RELEASE_REPO")"
  fi
  [[ -n "$tag" ]] || die "Could not resolve a release tag."

  tarball="$(release_tarball_name)"
  sums_url="https://github.com/${RELEASE_REPO}/releases/download/${tag}/SHA256SUMS.txt"
  tb_url="https://github.com/${RELEASE_REPO}/releases/download/${tag}/${tarball}"

  log "Installing from $RELEASE_REPO @ $tag ($tarball)"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would download $sums_url"
    log "Would download $tb_url"
    log "Would extract into $LOCAL_ROOT and link binaries into $BIN_DIR"
    return 0
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  sums_path="$tmp/SHA256SUMS.txt"
  tb_path="$tmp/$tarball"

  curl -fsSL -H "Accept: application/octet-stream" -H "User-Agent: sloppy-install.sh" -o "$sums_path" "$sums_url" || die "Failed to download SHA256SUMS.txt"
  curl -fsSL -H "Accept: application/octet-stream" -H "User-Agent: sloppy-install.sh" -o "$tb_path" "$tb_url" || die "Failed to download $tarball"

  expected="$(expected_sha256_from_sums "$tarball" "$sums_path")"
  [[ -n "$expected" ]] || die "Checksum file did not include an entry for $tarball."
  actual="$(sha256_file "$tb_path")"
  [[ "$expected" == "$actual" ]] || die "SHA256 mismatch for $tarball (expected $expected, got $actual)."

  run_cmd mkdir -p "$LOCAL_ROOT"
  run_cmd tar -C "$LOCAL_ROOT" -xzf "$tb_path"

  local default_dash="$LOCAL_ROOT/share/sloppy/dashboard"
  if [[ "$DASHBOARD_DIR" != "$default_dash" ]]; then
    log "Installing dashboard bundle into $DASHBOARD_DIR"
    run_cmd mkdir -p "$DASHBOARD_DIR"
    run_cmd rm -rf "${DASHBOARD_DIR:?}/dist" "${DASHBOARD_DIR:?}/config.json"
    run_cmd cp -R "$default_dash/dist" "$DASHBOARD_DIR/dist"
    run_cmd cp "$default_dash/config.json" "$DASHBOARD_DIR/config.json"
  fi

  if [[ "$NO_LINK" == "1" ]]; then
    log "Skipping command symlinks (--no-link)."
  else
    local sloppy_bin sloppy_node
    sloppy_bin="$LOCAL_ROOT/bin/sloppy"
    sloppy_node="$LOCAL_ROOT/bin/SloppyNode"
    log "Installing command symlinks into $BIN_DIR"
    run_cmd mkdir -p "$BIN_DIR"
    run_cmd ln -sf "$sloppy_bin" "$BIN_DIR/sloppy"
    run_cmd ln -sf "$sloppy_node" "$BIN_DIR/SloppyNode"
  fi

  trap - EXIT
  rm -rf "$tmp"

  log
  log "Install complete (release)."
  log "  Release: $tag"
  log "  Binaries: $LOCAL_ROOT/bin"
  log "  Dashboard: ${DASHBOARD_DIR}"
  if [[ "$NO_LINK" == "1" ]]; then
    log "  CLI: run $LOCAL_ROOT/bin/sloppy"
  else
    log "  CLI links: $BIN_DIR/sloppy and $BIN_DIR/SloppyNode"
  fi
  log
  log "Next steps:"
  log "  sloppy --version"
  log "  sloppy run"
}

checkout_is_clean() {
  local repo_root="$1"
  local status
  status="$(git -C "$repo_root" status --porcelain --untracked-files=no 2>/dev/null || true)"
  [[ -z "$status" ]]
}

prepare_checkout() {
  local existing_checkout=""
  if [[ "$INSTALL_DIR_SET" != "1" ]] && existing_checkout="$(current_checkout_root)"; then
    debug "Using current checkout at $existing_checkout"
    printf '%s\n' "$existing_checkout"
    return 0
  fi

  local target_dir="$INSTALL_DIR"
  if [[ -d "$target_dir/.git" ]]; then
    if [[ "$NO_GIT_UPDATE" == "1" ]]; then
      printf '%s\n' "Using existing checkout at $target_dir" >&2
    elif checkout_is_clean "$target_dir"; then
      printf '%s\n' "Updating existing checkout at $target_dir" >&2
      run_cmd git -C "$target_dir" pull --rebase
    else
      warn "Existing checkout at $target_dir has local changes. Skipping git pull."
    fi
  elif [[ -e "$target_dir" ]]; then
    die "Install directory '$target_dir' exists but is not a git checkout."
  else
    printf '%s\n' "Cloning Sloppy into $target_dir" >&2
    run_cmd mkdir -p "$(dirname "$target_dir")"
    run_cmd git clone "$REPO_URL" "$target_dir"
  fi

  printf '%s\n' "$target_dir"
}

build_server_stack() {
  local repo_root="$1"
  log "Resolving Swift packages"
  run_cmd swift package resolve --package-path "$repo_root"

  log "Building sloppy (release)"
  run_cmd swift build -c release --package-path "$repo_root" --product sloppy

  log "Building SloppyNode (release)"
  run_cmd swift build -c release --package-path "$repo_root" --product SloppyNode
}

build_dashboard() {
  local repo_root="$1"
  local dashboard_dir="$repo_root/Dashboard"
  local dashboard_entry="$dashboard_dir/node_modules/vite/bin/vite.js"
  log "Installing Dashboard dependencies"
  run_cmd npm install --prefix "$dashboard_dir"

  if [[ "$DRY_RUN" != "1" && ! -f "$dashboard_entry" ]]; then
    die "Dashboard build tool is missing at $dashboard_entry after npm install."
  fi

  log "Building Dashboard bundle"
  run_cmd node "$dashboard_entry" build --config "$dashboard_dir/vite.config.js"
}

install_dashboard_bundle() {
  local repo_root="$1"
  local dashboard_source="$repo_root/Dashboard"

  log "Installing Dashboard bundle into $DASHBOARD_DIR"
  run_cmd mkdir -p "$DASHBOARD_DIR"
  run_cmd rm -rf "$DASHBOARD_DIR/dist"
  run_cmd cp -R "$dashboard_source/dist" "$DASHBOARD_DIR/dist"
  run_cmd cp "$dashboard_source/config.json" "$DASHBOARD_DIR/config.json"
}

link_binaries() {
  local repo_root="$1"

  if [[ "$NO_LINK" == "1" ]]; then
    log "Skipping binary symlink installation because --no-link was provided"
    return 0
  fi

  local bin_path
  if [[ "$DRY_RUN" == "1" ]]; then
    bin_path="$repo_root/.build/release"
  else
    bin_path="$(swift build --show-bin-path -c release --package-path "$repo_root")"
  fi

  log "Installing command symlinks into $BIN_DIR"
  run_cmd mkdir -p "$BIN_DIR"
  run_cmd ln -sf "$bin_path/sloppy" "$BIN_DIR/sloppy"
  run_cmd ln -sf "$bin_path/SloppyNode" "$BIN_DIR/SloppyNode"
}

print_summary() {
  local repo_root="$1"

  log
  log "Install complete."
  log "  Checkout: $repo_root"
  if [[ "$MODE" == "bundle" ]]; then
    log "  Mode: full bundle (server + dashboard)"
    log "  Dashboard bundle: $DASHBOARD_DIR"
  else
    log "  Mode: server only"
    log "  Dashboard bundle: skipped"
  fi
  if [[ "$NO_LINK" == "1" ]]; then
    log "  CLI links: skipped"
  else
    log "  CLI links: $BIN_DIR/sloppy and $BIN_DIR/SloppyNode"
  fi
  log
  log "Next steps:"
  if [[ "$NO_LINK" == "1" ]]; then
    log "  1. Start the server from the checkout:"
    log "     cd \"$repo_root\" && swift run sloppy run"
  else
    log "  1. Start the server:"
    log "     sloppy run"
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
      log "     If 'sloppy' is not found, add this to your shell profile:"
      log "     export PATH=\"$BIN_DIR:\$PATH\""
    fi
  fi

  if [[ "$MODE" == "bundle" ]]; then
    log "  2. Dashboard GUI is installed and ready for \`sloppy run\`."
    log "     Frontend development server remains available at:"
    log "     cd \"$repo_root/Dashboard\" && npm run dev"
  else
    log "  2. Dashboard bundle was intentionally skipped. Re-run with --bundle if you want GUI support."
  fi

  log "  3. Verify the backend:"
  if [[ "$NO_LINK" == "1" ]]; then
    log "     cd \"$repo_root\" && swift run sloppy --version"
  else
    log "     sloppy --version"
    log "     sloppy status"
  fi
}

main() {
  parse_args "$@"
  ensure_mode
  ensure_prerequisites

  if [[ "$MODE" == "release" ]]; then
    install_from_github_release
    return 0
  fi

  local repo_root
  repo_root="$(prepare_checkout)"
  build_server_stack "$repo_root"
  if [[ "$MODE" == "bundle" ]]; then
    build_dashboard "$repo_root"
    install_dashboard_bundle "$repo_root"
  fi
  link_binaries "$repo_root"
  print_summary "$repo_root"
}

main "$@"
