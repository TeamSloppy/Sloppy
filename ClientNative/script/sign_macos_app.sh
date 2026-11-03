#!/bin/bash

set -euo pipefail

APP_PATH="${1:?usage: sign_macos_app.sh APP_PATH [SIGNING_IDENTITY] [ENTITLEMENTS]}"
IDENTITY="${2:-${MACOS_SIGNING_IDENTITY:-auto}}"
ENTITLEMENTS="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$IDENTITY" == "auto" ]]; then
    # Match the project's team, never an unrelated certificate on this Mac.
    TEAM_ID="${MACOS_SIGNING_TEAM_ID:-$(awk '/DEVELOPMENT_TEAM:/ { print $2; exit }' "$SCRIPT_DIR/../project.yml")}"
    IDENTITIES="$(security find-identity -v -p codesigning)"
    IDENTITY="$(printf '%s\n' "$IDENTITIES" | awk -v team="$TEAM_ID" '
        /"Developer ID Application:/ && index($0, "(" team ")") { print $2; exit }
    ')"
    if [[ -z "$IDENTITY" ]]; then
        IDENTITY="$(printf '%s\n' "$IDENTITIES" | awk -v team="$TEAM_ID" '
            /"Apple Development:/ && index($0, "(" team ")") { print $2; exit }
        ')"
    fi
    if [[ -z "$IDENTITY" ]]; then
        echo "warning: no signing certificate for team $TEAM_ID; ad hoc builds may prompt for Keychain access after each rebuild. Set MACOS_SIGNING_IDENTITY to use a stable certificate." >&2
        IDENTITY="-"
    fi
fi

SIGNING_OPTIONS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
    SIGNING_OPTIONS+=(--timestamp --options runtime)
fi
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
VERSION="$FRAMEWORK/Versions/Current"

# Sign Sparkle helpers before their containing framework and application.
for PATH_TO_SIGN in \
    "$VERSION/XPCServices/Downloader.xpc" \
    "$VERSION/XPCServices/Installer.xpc" \
    "$VERSION/Autoupdate" \
    "$VERSION/Updater.app" \
    "$FRAMEWORK"; do
    if [[ ! -e "$PATH_TO_SIGN" ]]; then
        echo "error: signing input was not found at $PATH_TO_SIGN" >&2
        exit 1
    fi
    codesign "${SIGNING_OPTIONS[@]}" \
        --preserve-metadata=identifier,entitlements "$PATH_TO_SIGN"
done

# Xcode's Debug executable loads its application code from a sibling dylib.
# Its linker signature has no Team ID and cannot pass library validation in a
# certificate-signed application. Sign these libraries before sealing the app.
for DEBUG_LIBRARY in "$APP_PATH/Contents/MacOS/"*.dylib; do
    [[ -f "$DEBUG_LIBRARY" ]] || continue
    codesign "${SIGNING_OPTIONS[@]}" \
        --preserve-metadata=identifier "$DEBUG_LIBRARY"
done

APP_SIGNING_OPTIONS=(--preserve-metadata=entitlements)
if [[ -n "$ENTITLEMENTS" ]]; then
    APP_SIGNING_OPTIONS=(--entitlements "$ENTITLEMENTS")
    # Raw source plists contain Xcode variables and managed capabilities. Resolve
    # them against the actual profile before sealing a launchable application.
    KVS_KEY="com.apple.developer.ubiquity-kvstore-identifier"
    PASSKEY_KEY="com.apple.developer.web-browser.public-key-credential"
    if /usr/libexec/PlistBuddy -c "Print :$KVS_KEY" "$ENTITLEMENTS" >/dev/null 2>&1 || \
       /usr/libexec/PlistBuddy -c "Print :$PASSKEY_KEY" "$ENTITLEMENTS" >/dev/null 2>&1; then
        SIGNING_ENTITLEMENTS_DIR="$(mktemp -d)"
        trap 'rm -rf "$SIGNING_ENTITLEMENTS_DIR"' EXIT
        FILTERED_ENTITLEMENTS="$SIGNING_ENTITLEMENTS_DIR/SloppyClient.entitlements"
        PROFILE="$APP_PATH/Contents/embedded.provisionprofile"
        # This profile belongs to the browser, never to Sparkle or the companion.
        SUPPLIED_PROFILE="${MACOS_PASSKEY_PROVISIONING_PROFILE:-}"
        if [[ -n "$SUPPLIED_PROFILE" ]]; then
            PROFILE="$SUPPLIED_PROFILE"
        fi
        PROFILE_PLIST=""
        if [[ "$IDENTITY" != "-" && -f "$PROFILE" ]]; then
            PROFILE_PLIST="$SIGNING_ENTITLEMENTS_DIR/profile.plist"
            security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
        elif [[ -n "$SUPPLIED_PROFILE" ]]; then
            echo "error: supplied passkey profile is missing or the signing identity is ad hoc" >&2
            exit 1
        fi
        TEAM_ID="${MACOS_SIGNING_TEAM_ID:-$(awk '/DEVELOPMENT_TEAM:/ { print $2; exit }' "$SCRIPT_DIR/../project.yml")}"
        python3 "$SCRIPT_DIR/prepare_macos_entitlements.py" "$ENTITLEMENTS" "$FILTERED_ENTITLEMENTS" \
            "$BUNDLE_IDENTIFIER" "$TEAM_ID" "$IDENTITY" "$PROFILE_PLIST"
        if [[ -n "$SUPPLIED_PROFILE" ]]; then
            if [[ "$(/usr/libexec/PlistBuddy -c "Print :$PASSKEY_KEY" "$FILTERED_ENTITLEMENTS" 2>/dev/null || true)" != "true" ]]; then
                echo "error: supplied profile does not authorize browser passkeys" >&2
                exit 1
            fi
            if [[ "$PROFILE" != "$APP_PATH/Contents/embedded.provisionprofile" ]]; then
                cp "$PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
            fi
        fi
        APP_SIGNING_OPTIONS=(--entitlements "$FILTERED_ENTITLEMENTS")
    fi
fi
codesign "${SIGNING_OPTIONS[@]}" "${APP_SIGNING_OPTIONS[@]}" \
    --identifier "$BUNDLE_IDENTIFIER" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
