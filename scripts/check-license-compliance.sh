#!/usr/bin/env bash

set -euo pipefail

required=(
  LICENSE
  LICENSES/MIT.txt
  LICENSES/README.md
  SOURCE_OFFER.md
  THIRD_PARTY_NOTICES.md
  CLA.md
)

for path in "${required[@]}"; do
  if [[ ! -s "$path" ]]; then
    echo "missing required licensing file: $path" >&2
    exit 1
  fi
done

if ! grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" LICENSE; then
  echo "root LICENSE is not the AGPL-3.0 text" >&2
  exit 1
fi

if ! grep -q "AGPL--3.0" README.md; then
  echo "README license badge is not AGPL-3.0" >&2
  exit 1
fi

if ! grep -q '"license": "AGPL-3.0-only"' Dashboard/package.json; then
  echo "Dashboard package is missing AGPL metadata" >&2
  exit 1
fi

for package in Plugins/sdk/nodejs/package.json Plugins/examples/*/package.json Apps/SloppySafari/Extension/package.json; do
  if ! grep -q '"license": "MIT"' "$package"; then
    echo "MIT integration package is missing MIT metadata: $package" >&2
    exit 1
  fi
done

if command -v node >/dev/null 2>&1; then
  node <<'NODE'
const allowed = new Set([
  "(Apache-2.0 OR MIT)",
  "(BSD-3-Clause AND Apache-2.0)",
  "(MPL-2.0 OR Apache-2.0)",
  "0BSD",
  "AGPL-3.0-only",
  "Apache-2.0",
  "BSD-2-Clause",
  "BSD-3-Clause",
  "CC0-1.0",
  "ISC",
  "MIT",
  "MIT AND ISC",
  "Unlicense",
  "apache-2.0",
]);
for (const path of ["Dashboard/package-lock.json", "docs/package-lock.json"]) {
  const lock = require(`${process.cwd()}/${path}`);
  for (const [name, entry] of Object.entries(lock.packages ?? {})) {
    if (entry.license && !allowed.has(entry.license)) {
      throw new Error(`unreviewed npm license in ${path}: ${name || "<root>"} = ${entry.license}`);
    }
  }
}
NODE
else
  echo "node is required to scan npm lockfile licenses" >&2
  exit 1
fi

if [[ "${1:-}" == "--check-resolved" ]]; then
  if [[ ! -d .build/checkouts ]]; then
    echo "run swift package resolve before --check-resolved" >&2
    exit 1
  fi
  missing=0
  while IFS= read -r checkout; do
    if ! find "$checkout" -maxdepth 3 -type f \
      \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) \
      | grep -q .; then
      echo "resolved dependency has no discoverable license: $checkout" >&2
      missing=1
    fi
  done < <(find .build/checkouts -mindepth 1 -maxdepth 1 -type d | sort)
  if [[ $missing -ne 0 ]]; then
    exit 1
  fi
fi

echo "license compliance checks passed"
