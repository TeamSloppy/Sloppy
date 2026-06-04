#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
DEFAULT_DEST="Sources/sloppy/Resources/Skills"
DEST_DIR="${SLOPPY_SKILLS_DEST:-$DEFAULT_DEST}"
REF="${SLOPPY_SKILLS_REF:-main}"
FORCE=0
DRY_RUN="${SLOPPY_DRY_RUN:-0}"
VERBOSE="${SLOPPY_VERBOSE:-0}"

SOURCES=(
  "https://github.com/NousResearch/hermes-agent/tree/main/skills"
)

log() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
debug() { [[ "$VERBOSE" == "1" ]] && printf 'debug: %s\n' "$*" >&2 || true; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] [github-skill-url ...]

Download skill directories into Sloppy's SwiftPM resource bundle so they are
shipped with the sloppy executable and provisioned out of the box.

By default the script downloads skills from:
  https://github.com/NousResearch/hermes-agent/tree/main/skills

Options:
  --source <url>   Add a GitHub tree URL to download. May be passed multiple times.
  --dest <path>    Destination bundle directory. Default: $DEFAULT_DEST
  --ref <ref>      Git ref/branch to use when source URL omits one. Default: main
  --force          Replace existing downloaded skill directories.
  --dry-run        Print actions without writing files.
  --verbose        Print debug logs.
  --help, -h       Show this help.

Supported source URL forms:
  https://github.com/<owner>/<repo>/tree/<ref>/<path>
  https://github.com/<owner>/<repo>[/tree/<ref>/<path>]
  <owner>/<repo>[:<path>]

Environment:
  SLOPPY_SKILLS_DEST=$DEFAULT_DEST
  SLOPPY_SKILLS_REF=main
  SLOPPY_DRY_RUN=1
  SLOPPY_VERBOSE=1
  GITHUB_TOKEN=<token>  (optional, avoids GitHub API rate limits)
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found."
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  "$@"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9._-]+#-#g; s#^-+##; s#-+$##'
}

parse_source() {
  local source="$1"
  local gh_owner gh_repo gh_ref gh_path rest

  if [[ "$source" =~ ^https://github\.com/([^/]+)/([^/]+)(/tree/([^/]+)(/(.*))?)?/?$ ]]; then
    gh_owner="${BASH_REMATCH[1]}"
    gh_repo="${BASH_REMATCH[2]%.git}"
    gh_ref="${BASH_REMATCH[4]:-$REF}"
    gh_path="${BASH_REMATCH[6]:-}"
  elif [[ "$source" =~ ^([^/:]+)/([^/:]+)(:(.*))?$ ]]; then
    gh_owner="${BASH_REMATCH[1]}"
    gh_repo="${BASH_REMATCH[2]%.git}"
    gh_ref="$REF"
    gh_path="${BASH_REMATCH[4]:-}"
  else
    die "Unsupported source URL: $source"
  fi

  printf '%s\t%s\t%s\t%s\n' "$gh_owner" "$gh_repo" "$gh_ref" "$gh_path"
}

api_get() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "$url"
  fi
}

raw_get() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$url"
  else
    curl -fsSL "$url"
  fi
}

download_file() {
  local url="$1"
  local dest="$2"
  debug "download $url -> $dest"
  run_cmd mkdir -p "$(dirname "$dest")"
  if [[ "$DRY_RUN" == "1" ]]; then
    run_cmd sh -c "printf '%s\n' '# dry-run placeholder from $url' > '$dest'"
  else
    raw_get "$url" > "$dest"
  fi
}

download_tree() {
  local gh_owner="$1"
  local gh_repo="$2"
  local gh_ref="$3"
  local tree_path="$4"
  local dest_root="$5"
  local base_path="${6:-$tree_path}"
  local api_path="repos/$gh_owner/$gh_repo/contents"
  [[ -n "$tree_path" ]] && api_path="$api_path/$tree_path"
  local api_url="https://api.github.com/$api_path?ref=$gh_ref"

  debug "list $api_url"
  local json
  json="$(api_get "$api_url")"

  JSON_PAYLOAD="$json" python3 - "$dest_root" <<'PY' | while IFS=$'\t' read -r item_type item_name item_path item_download; do
import json, os, sys
payload = json.loads(os.environ["JSON_PAYLOAD"])
if isinstance(payload, dict):
    payload = [payload]
for item in payload:
    print("\t".join([
        item.get("type", ""),
        item.get("name", ""),
        item.get("path", ""),
        item.get("download_url") or ""
    ]))
PY
    if [[ "$item_type" == "dir" ]]; then
      download_tree "$gh_owner" "$gh_repo" "$gh_ref" "$item_path" "$dest_root" "$base_path"
    elif [[ "$item_type" == "file" ]]; then
      [[ -n "$item_download" ]] || continue
      local rel="$item_path"
      if [[ -n "$base_path" && "$rel" == "$base_path"/* ]]; then
        rel="${rel#"$base_path"/}"
      fi
      download_file "$item_download" "$dest_root/$rel"
    fi
  done
}

install_skill_dir() {
  local gh_owner="$1"
  local gh_repo="$2"
  local gh_ref="$3"
  local skill_path="$4"
  local skill_name
  skill_name="$(basename "$skill_path")"
  local slug
  slug="$(slugify "$skill_name")"
  [[ -n "$slug" ]] || die "Could not derive skill slug from $skill_path"

  local dest="$DEST_DIR/$slug"
  if [[ -e "$dest" && "$FORCE" != "1" ]]; then
    warn "Skipping existing skill '$slug' at $dest (use --force to replace)."
    return 0
  fi

  if [[ -e "$dest" ]]; then
    run_cmd rm -rf "$dest"
  fi

  log "Downloading $gh_owner/$gh_repo:$skill_path@$gh_ref -> $dest"
  download_tree "$gh_owner" "$gh_repo" "$gh_ref" "$skill_path" "$dest"

  if [[ "$DRY_RUN" != "1" && ! -f "$dest/SKILL.md" ]]; then
    warn "Downloaded '$slug' but no SKILL.md was found at the skill root. Runtime will ignore this directory."
  fi
}

download_source() {
  local source="$1"
  local parsed gh_owner gh_repo gh_ref gh_path
  parsed="$(parse_source "$source")"
  IFS=$'\t' read -r gh_owner gh_repo gh_ref gh_path <<< "$parsed"

  log "Discovering skills from $gh_owner/$gh_repo:${gh_path:-.}@$gh_ref"
  local api_path="repos/$gh_owner/$gh_repo/contents"
  [[ -n "$gh_path" ]] && api_path="$api_path/$gh_path"
  local api_url="https://api.github.com/$api_path?ref=$gh_ref"
  local json
  json="$(api_get "$api_url")"

  JSON_PAYLOAD="$json" python3 - <<'PY' | while IFS=$'\t' read -r item_type item_path; do
import json, os
payload = json.loads(os.environ["JSON_PAYLOAD"])
if isinstance(payload, dict):
    payload = [payload]
for item in payload:
    if item.get("type") == "dir":
        print("\t".join(["dir", item.get("path", "")]))
    elif item.get("type") == "file" and item.get("name", "").lower() == "skill.md":
        parent = "/".join(item.get("path", "").split("/")[:-1])
        print("\t".join(["skill", parent]))
PY
    [[ -n "$item_path" ]] || continue
    install_skill_dir "$gh_owner" "$gh_repo" "$gh_ref" "$item_path"
  done
}

parse_args() {
  local custom_sources=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        [[ $# -ge 2 ]] || die "--source requires a value"
        custom_sources+=("$2")
        shift 2
        ;;
      --dest)
        [[ $# -ge 2 ]] || die "--dest requires a value"
        DEST_DIR="$2"
        shift 2
        ;;
      --ref)
        [[ $# -ge 2 ]] || die "--ref requires a value"
        REF="$2"
        shift 2
        ;;
      --owner)
        [[ $# -ge 2 ]] || die "--owner requires a value"
        OWNER="$2"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --verbose)
        VERBOSE=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        die "Unknown argument: $1"
        ;;
      *)
        custom_sources+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#custom_sources[@]} -gt 0 ]]; then
    SOURCES=("${custom_sources[@]}")
  fi
}

main() {
  parse_args "$@"
  require_command curl
  require_command python3

  run_cmd mkdir -p "$DEST_DIR"
  for source in "${SOURCES[@]}"; do
    download_source "$source"
  done
  log "Done. Bundled skills directory: $DEST_DIR"
}

main "$@"
