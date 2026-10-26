#!/usr/bin/env bash
set -euo pipefail
stage="${1:?usage: bundle-linux-runtime.sh STAGE}"
executable="$stage/bin/sloppy"
runtime="$stage/bin/lib"
licenses="$stage/share/sloppy/licenses/system-runtime"
mkdir -p "$runtime" "$licenses"
# Keep glibc and its loader supplied by the supported OS; bundle the Swift,
# Foundation and other shared libraries resolved for this release binary.
while IFS= read -r dependency; do
  name="${dependency##*/}"
  case "$name" in
    libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|ld-linux*) continue ;;
  esac
  cp -L "$dependency" "$runtime/$name"
  package="$(dpkg-query -S "$(readlink -f "$dependency")" 2>/dev/null | head -1 | cut -d: -f1 || true)"
  if [[ -n "$package" && -f "/usr/share/doc/$package/copyright" ]]; then
    cp -L "/usr/share/doc/$package/copyright" "$licenses/$package.txt"
  fi
done < <(ldd "$executable" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }')
patchelf --set-rpath '$ORIGIN/lib' "$executable"
for library in "$runtime/"*; do
  [[ ! -f "$library" ]] || patchelf --set-rpath '$ORIGIN' "$library"
done
if ldd "$executable" | grep -q 'not found'; then
  echo 'error: unresolved library in Linux release package' >&2
  exit 1
fi
cat > "$licenses/Swift-runtime.txt" <<'NOTICE'
Swift and Foundation runtime libraries: Apache License 2.0 with Runtime Library Exception.
https://github.com/swiftlang/swift/blob/main/LICENSE.txt
NOTICE
