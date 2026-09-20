#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NotchPetAdaPrototype"
BUNDLE_ID="team.sloppy.notch-pet-ada-prototype"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
MODULE_CACHE="$ROOT_DIR/.build/module-cache"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ADAENGINE_CACHE="${ADAENGINE_CACHE_PATH:-$ROOT_DIR/.swiftpm-cache}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE"

BUILD_OPTIONS=(--disable-sandbox --disable-automatic-resolution --package-path "$ROOT_DIR")
if [[ -d "$ADAENGINE_CACHE" ]]; then
  BUILD_OPTIONS+=(--cache-path "$ADAENGINE_CACHE")
fi

swift build "${BUILD_OPTIONS[@]}"
BIN_PATH="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"
BUILD_BINARY="$BIN_PATH/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

find "$BIN_PATH" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "$APP_RESOURCES/" \;

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Ada Notch Pet</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
