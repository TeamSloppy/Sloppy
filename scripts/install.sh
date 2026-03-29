#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
REPO_URL="${SLOPPY_REPO_URL:-https://github.com/TeamSloppy/Sloppy.git}"
INSTALL_DIR="${SLOPPY_INSTALL_DIR:-$HOME/.local/share/sloppy/source}"
BIN_DIR="${SLOPPY_BIN_DIR:-$HOME/.local/bin}"
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

Install Sloppy from source and optionally build the Dashboard bundle.

Options:
  --bundle            Build the server stack and Dashboard bundle.
  --server-only       Build only the server stack.
  --dir <path>        Clone or update the Sloppy checkout in <path> when not running inside a checkout.
  --bin-dir <path>    Install command symlinks into <path>. Default: $BIN_DIR
  --no-link           Do not create symlinks for sloppy and SloppyNode.
  --no-git-update     Do not pull an existing checkout before building.
  --no-prompt         Disable interactive prompts and use defaults.
  --dry-run           Print the actions without executing them.
  --verbose           Enable verbose installer logs.
  --help, -h          Show this help.

Environment variables:
  SLOPPY_INSTALL_MODE=bundle|server
  SLOPPY_INSTALL_DIR=/path/to/checkout
  SLOPPY_BIN_DIR=/path/to/bin
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
      bundle|server) return 0 ;;
      *)
        die "Unsupported install mode '$MODE'. Use 'bundle' or 'server'."
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
  printf 'Selection [1]: '
  read -r selection
  case "$selection" in
    ""|1)
      MODE="bundle"
      ;;
    2)
      MODE="server"
      ;;
    *)
      die "Invalid selection '$selection'."
      ;;
  esac
}

ensure_prerequisites() {
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
  log "Installing Dashboard dependencies"
  run_cmd npm install --prefix "$dashboard_dir"

  log "Building Dashboard bundle"
  run_cmd npm run --prefix "$dashboard_dir" build
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
  else
    log "  Mode: server only"
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
    log "  2. Start the Dashboard dev server when needed:"
    log "     cd \"$repo_root/Dashboard\" && npm run dev"
  else
    log "  2. Dashboard build was skipped. Re-run with --bundle if you want it."
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

  local repo_root
  repo_root="$(prepare_checkout)"
  build_server_stack "$repo_root"
  if [[ "$MODE" == "bundle" ]]; then
    build_dashboard "$repo_root"
  fi
  link_binaries "$repo_root"
  print_summary "$repo_root"
}

main "$@"
