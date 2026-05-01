#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
BIN_DIR="${SLOPPY_BIN_DIR:-$HOME/.local/bin}"
DASHBOARD_DIR="${SLOPPY_DASHBOARD_DIR:-$HOME/.local/share/sloppy/dashboard}"
LOCAL_ROOT="${SLOPPY_LOCAL_ROOT:-$HOME/.local}"
INSTALL_DIR="${SLOPPY_INSTALL_DIR:-$HOME/.local/share/sloppy/source}"
DRY_RUN="${SLOPPY_DRY_RUN:-0}"
REMOVE_SOURCE_CHECKOUT="${SLOPPY_REMOVE_SOURCE_CHECKOUT:-0}"

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

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Remove Sloppy binaries and dashboard assets installed by scripts/install.sh.

Options:
  --bin-dir <path>              Directory containing the sloppy command. Default: $BIN_DIR
  --dashboard-dir <path>        Dashboard bundle directory. Default: $DASHBOARD_DIR
  --local-root <path>           Release layout root. Default: $LOCAL_ROOT
  --install-dir <path>          Source checkout directory. Default: $INSTALL_DIR
  --remove-source-checkout      Also remove the source checkout created/used for source installs
  --dry-run                     Print what would be removed without deleting anything
  --help, -h                    Show this help

Environment variables:
  SLOPPY_BIN_DIR=/path/to/bin
  SLOPPY_DASHBOARD_DIR=/path/to/dashboard
  SLOPPY_LOCAL_ROOT=$HOME/.local
  SLOPPY_INSTALL_DIR=/path/to/checkout
  SLOPPY_REMOVE_SOURCE_CHECKOUT=1
  SLOPPY_DRY_RUN=1
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

remove_file_if_exists() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    run_cmd rm -f "$path"
    return 0
  fi
  return 1
}

remove_dir_if_exists() {
  local path="$1"
  if [[ -d "$path" ]]; then
    run_cmd rm -rf "$path"
    return 0
  fi
  return 1
}

remove_dir_contents_if_present() {
  local dir="$1"
  local removed=1

  if [[ -d "$dir/dist" ]]; then
    run_cmd rm -rf "$dir/dist"
    removed=0
  fi
  if [[ -f "$dir/config.json" ]]; then
    run_cmd rm -f "$dir/config.json"
    removed=0
  fi

  if [[ "$removed" -eq 0 ]]; then
    run_cmd rmdir "$dir" 2>/dev/null || true
  fi
  return "$removed"
}

remove_dir_if_empty() {
  local path="$1"
  [[ -d "$path" ]] || return 0
  run_cmd rmdir "$path" 2>/dev/null || true
}

is_probable_sloppy_checkout() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  [[ -f "$path/Package.swift" && -f "$path/Dashboard/package.json" ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --local-root)
        [[ $# -ge 2 ]] || die "--local-root requires a value"
        LOCAL_ROOT="$2"
        shift 2
        ;;
      --install-dir)
        [[ $# -ge 2 ]] || die "--install-dir requires a value"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --remove-source-checkout)
        REMOVE_SOURCE_CHECKOUT="1"
        shift
        ;;
      --dry-run)
        DRY_RUN="1"
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

main() {
  parse_args "$@"

  local release_bin_dir default_dashboard_dir removed_any=1
  release_bin_dir="$LOCAL_ROOT/bin"
  default_dashboard_dir="$LOCAL_ROOT/share/sloppy/dashboard"

  if remove_file_if_exists "$BIN_DIR/sloppy"; then
    removed_any=0
  fi

  if [[ "$release_bin_dir" != "$BIN_DIR" ]]; then
    if remove_file_if_exists "$release_bin_dir/sloppy"; then
      removed_any=0
    fi
  fi

  if remove_dir_contents_if_present "$DASHBOARD_DIR"; then
    :
  else
    removed_any=0
  fi

  if [[ "$default_dashboard_dir" != "$DASHBOARD_DIR" ]]; then
    if remove_dir_contents_if_present "$default_dashboard_dir"; then
      :
    else
      removed_any=0
    fi
  fi

  if [[ "$REMOVE_SOURCE_CHECKOUT" == "1" ]]; then
    if is_probable_sloppy_checkout "$INSTALL_DIR"; then
      if remove_dir_if_exists "$INSTALL_DIR"; then
        removed_any=0
      fi
    elif [[ -e "$INSTALL_DIR" ]]; then
      warn "Skipping source checkout removal for '$INSTALL_DIR' because it does not look like a Sloppy checkout."
    fi
  fi

  remove_dir_if_empty "$release_bin_dir"
  remove_dir_if_empty "$LOCAL_ROOT/share/sloppy"
  remove_dir_if_empty "$LOCAL_ROOT/share"

  if [[ "$removed_any" -eq 0 ]]; then
    log "Sloppy uninstall complete."
    log "  Removed command links/binaries from: $BIN_DIR"
    if [[ "$release_bin_dir" != "$BIN_DIR" ]]; then
      log "  Removed release binaries from: $release_bin_dir"
    fi
    log "  Removed dashboard assets from: $DASHBOARD_DIR"
    if [[ "$default_dashboard_dir" != "$DASHBOARD_DIR" ]]; then
      log "  Removed extracted release dashboard from: $default_dashboard_dir"
    fi
    if [[ "$REMOVE_SOURCE_CHECKOUT" == "1" ]]; then
      log "  Removed source checkout: $INSTALL_DIR"
    fi
  else
    log "Nothing to remove."
  fi
}

main "$@"
