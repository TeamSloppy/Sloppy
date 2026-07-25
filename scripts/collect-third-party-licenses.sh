#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: $0 DESTINATION" >&2
  exit 64
fi

destination="$1"
mkdir -p "$destination"

roots=()
if [[ -d .build/checkouts ]]; then
  while IFS= read -r checkout; do
    roots+=("$checkout")
  done < <(find .build/checkouts -mindepth 1 -maxdepth 1 -type d | sort)
fi

for bundled in Packages/TauTUI Vendor/AdaEngine Vendor/AdaMCP; do
  if [[ -d "$bundled" ]]; then
    roots+=("$bundled")
  fi
done

if [[ ${#roots[@]} -eq 0 ]]; then
  echo "no resolved or bundled dependencies found" >&2
  exit 1
fi

copied=0
for root in "${roots[@]}"; do
  dependency="$(basename "$root")"
  dependency_destination="$destination/$dependency"
  while IFS= read -r notice; do
    mkdir -p "$dependency_destination"
    relative="${notice#"$root"/}"
    safe_name="${relative//\//__}"
    cp "$notice" "$dependency_destination/$safe_name"
    copied=$((copied + 1))
  done < <(
    find "$root" -maxdepth 3 -type f \
      \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'NOTICE' -o -iname 'NOTICE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) \
      | sort
  )
done

if [[ $copied -eq 0 ]]; then
  echo "no third-party license or notice files found" >&2
  exit 1
fi

echo "collected $copied third-party license/notice files"
