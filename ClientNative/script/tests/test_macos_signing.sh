#!/usr/bin/env bash
set -euo pipefail

SIGNING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$SIGNING_TEST_ROOT"' EXIT
export SIGNING_TEST_LOG="$SIGNING_TEST_ROOT/codesign.log"
export SIGNING_TEST_IDENTITIES="$SIGNING_TEST_ROOT/identities"
mkdir -p "$SIGNING_TEST_ROOT/bin"
cat > "$SIGNING_TEST_ROOT/bin/security" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == cms ]]; then cat "$SIGNING_TEST_PROFILE"; else cat "$SIGNING_TEST_IDENTITIES"; fi
SH
cat > "$SIGNING_TEST_ROOT/bin/codesign" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SIGNING_TEST_LOG"
while [[ $# -gt 1 ]]; do
    if [[ "$1" == --entitlements ]]; then cp "$2" "$SIGNING_TEST_LOG.entitlements"; break; fi
    shift
done
SH
chmod +x "$SIGNING_TEST_ROOT/bin/security" "$SIGNING_TEST_ROOT/bin/codesign"
export PATH="$SIGNING_TEST_ROOT/bin:$PATH"
export MACOS_SIGNING_TEAM_ID=8PYCRS3EA3
unset MACOS_SIGNING_IDENTITY

# Standalone Developer ID builds have no APNs provisioning profile.
for KEY in aps-environment com.apple.developer.aps-environment; do
    if /usr/libexec/PlistBuddy -c "Print :$KEY" "$SIGNING_SCRIPT_DIR/../SupportingFiles/macOS/SloppyClient.entitlements" >/dev/null 2>&1; then
        echo "error: standalone client includes a restricted push entitlement" >&2
        exit 1
    fi
done

APP="$SIGNING_TEST_ROOT/Sloppy.app"
VERSION="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
mkdir -p "$VERSION/XPCServices/Downloader.xpc" "$VERSION/XPCServices/Installer.xpc" "$VERSION/Updater.app"
touch "$VERSION/Autoupdate"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>team.sloppy.client</string></dict></plist>
PLIST
cat > "$SIGNING_TEST_IDENTITIES" <<'IDENTITIES'
1) WRONG "Developer ID Application: Other (OTHERTEAM)"
2) DEVELOPMENT "Apple Development: Developer (8PYCRS3EA3)"
3) DEVELOPERID "Developer ID Application: Developer (8PYCRS3EA3)"
IDENTITIES

bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP" auto "$SIGNING_SCRIPT_DIR/../SupportingFiles/macOS/SloppyClient.entitlements"
[[ "$(rg -c -- '--sign DEVELOPERID' "$SIGNING_TEST_LOG")" == 6 ]]
rg -q -- '--entitlements .*SloppyClient.entitlements --identifier team.sloppy.client' "$SIGNING_TEST_LOG"
! /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.ubiquity-kvstore-identifier' "$SIGNING_TEST_LOG.entitlements" >/dev/null 2>&1
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$SIGNING_TEST_LOG.entitlements" | rg -q true
[[ "$(tail -n 1 "$SIGNING_TEST_LOG")" == "--verify --deep --strict --verbose=2 $APP" ]]

# Provisioned signatures use the profile's concrete identifier, never raw Xcode variables.
export SIGNING_TEST_PROFILE="$SIGNING_TEST_ROOT/profile.plist"
cat > "$SIGNING_TEST_PROFILE" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Entitlements</key><dict>
<key>com.apple.developer.ubiquity-kvstore-identifier</key><string>8PYCRS3EA3.team.sloppy.client</string>
</dict></dict></plist>
PLIST
touch "$APP/Contents/embedded.provisionprofile"
bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP" auto "$SIGNING_SCRIPT_DIR/../SupportingFiles/macOS/SloppyClient.entitlements"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.ubiquity-kvstore-identifier' "$SIGNING_TEST_LOG.entitlements")" == '8PYCRS3EA3.team.sloppy.client' ]]
rm "$APP/Contents/embedded.provisionprofile"

# A development certificate is preferred to ad hoc when Developer ID is absent.
printf '%s\n' '1) DEVELOPMENT "Apple Development: Developer (8PYCRS3EA3)"' > "$SIGNING_TEST_IDENTITIES"
: > "$SIGNING_TEST_LOG"
bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP"
[[ "$(rg -c -- '--sign DEVELOPMENT' "$SIGNING_TEST_LOG")" == 6 ]]

# Never select another team's certificate; preserve the explicit override.
printf '%s\n' '1) WRONG "Developer ID Application: Other (OTHERTEAM)"' > "$SIGNING_TEST_IDENTITIES"
: > "$SIGNING_TEST_LOG"
bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP" auto 2> "$SIGNING_TEST_ROOT/warning"
[[ "$(rg -c -- '--sign - ' "$SIGNING_TEST_LOG")" == 6 ]]
rg -q 'ad hoc builds may prompt for Keychain' "$SIGNING_TEST_ROOT/warning"
! rg -q -- '--timestamp' "$SIGNING_TEST_LOG"
: > "$SIGNING_TEST_LOG"
bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP" EXPLICIT
[[ "$(rg -c -- '--sign EXPLICIT' "$SIGNING_TEST_LOG")" == 6 ]]

# Xcode Debug dylibs must use the same identity before the app is sealed.
mkdir -p "$APP/Contents/MacOS"
touch "$APP/Contents/MacOS/Sloppy.debug.dylib" "$APP/Contents/MacOS/__preview.dylib"
: > "$SIGNING_TEST_LOG"
bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP" EXPLICIT
[[ "$(rg -c -- '--sign EXPLICIT' "$SIGNING_TEST_LOG")" == 8 ]]
APP_SIGNING_LINE="$(awk '/--identifier team.sloppy.client / { print NR; exit }' "$SIGNING_TEST_LOG")"
for DEBUG_LIBRARY in "$APP/Contents/MacOS/"*.dylib; do
    LIBRARY_SIGNING_LINE="$(awk -v library="$DEBUG_LIBRARY" 'index($0, library) { print NR; exit }' "$SIGNING_TEST_LOG")"
    [[ -n "$LIBRARY_SIGNING_LINE" && "$LIBRARY_SIGNING_LINE" -lt "$APP_SIGNING_LINE" ]]
done

# A failed helper signature must abort before the containing app is signed.
cat > "$SIGNING_TEST_ROOT/bin/codesign" <<'SH'
#!/usr/bin/env bash
exit 1
SH
if bash "$SIGNING_SCRIPT_DIR/sign_macos_app.sh" "$APP" EXPLICIT; then
    echo "error: signing failure was ignored" >&2
    exit 1
fi
echo "macOS signing identity selection, nested signing, entitlements, and failures passed."
