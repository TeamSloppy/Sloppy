#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/SloppyClient.xcodeproj"
SCHEME="SloppyClient-macOS"
CONFIGURATION="Release"
DERIVED_DATA="${DERIVED_DATA:-$PROJECT_DIR/.build/install-derived-data}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
SHOULD_LAUNCH=1
ARCHITECTURE="$(uname -m)"

usage() {
    cat <<'EOF'
Build and install SloppyClient on this Mac.

Usage: script/build_and_install.sh [options]

Options:
  --debug              Build the Debug configuration instead of Release.
  --release            Build the Release configuration (default).
  --install-dir PATH   Install into PATH instead of /Applications.
  --no-launch          Do not launch the app after installation.
  -h, --help           Show this help.

Environment:
  DERIVED_DATA         Override the Xcode DerivedData directory.
  INSTALL_DIR          Override the installation directory.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIGURATION="Debug"
            shift
            ;;
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --install-dir)
            if [[ $# -lt 2 ]]; then
                echo "error: --install-dir requires a path" >&2
                exit 2
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --no-launch)
            SHOULD_LAUNCH=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: this script can only install the macOS application" >&2
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild is required; install Xcode first" >&2
    exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Generating the Xcode project"
    (
        cd "$PROJECT_DIR"
        xcodegen generate
    )
elif [[ ! -d "$PROJECT_FILE" ]]; then
    echo "error: xcodegen is required to generate $PROJECT_FILE" >&2
    echo "Install it with: brew install xcodegen" >&2
    exit 1
else
    echo "==> xcodegen is unavailable; using the existing Xcode project"
fi

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$ARCHITECTURE" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
SOURCE_APP="$PRODUCTS_DIR/SloppyClient-macOS.app"
if [[ ! -d "$SOURCE_APP" ]]; then
    SOURCE_APP="$PRODUCTS_DIR/SloppyClient.app"
fi
if [[ ! -d "$SOURCE_APP" ]]; then
    echo "error: built application was not found in $PRODUCTS_DIR" >&2
    exit 1
fi

BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$SOURCE_APP/Contents/Info.plist")"
if [[ "$BUNDLE_ID" != "team.sloppy.client" ]]; then
    echo "error: refusing to install an unexpected application ($BUNDLE_ID)" >&2
    exit 1
fi

DESTINATION_APP="${INSTALL_DIR%/}/SloppyClient.app"
TEMP_APP="${INSTALL_DIR%/}/.SloppyClient.install.$$"
BACKUP_APP="${INSTALL_DIR%/}/.SloppyClient.backup.$$"
USE_SUDO=0
INSTALL_COMPLETE=0

if [[ ! -d "$INSTALL_DIR" ]]; then
    if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        USE_SUDO=1
    fi
elif [[ ! -w "$INSTALL_DIR" ]]; then
    USE_SUDO=1
fi

if [[ $USE_SUDO -eq 1 ]] && ! command -v sudo >/dev/null 2>&1; then
    echo "error: $INSTALL_DIR is not writable and sudo is unavailable" >&2
    exit 1
fi

run_install_command() {
    if [[ $USE_SUDO -eq 1 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

cleanup() {
    set +e
    run_install_command rm -rf "$TEMP_APP"
    if [[ $INSTALL_COMPLETE -eq 0 && ! -e "$DESTINATION_APP" && -e "$BACKUP_APP" ]]; then
        run_install_command mv "$BACKUP_APP" "$DESTINATION_APP"
    fi
    if [[ $INSTALL_COMPLETE -eq 1 ]]; then
        run_install_command rm -rf "$BACKUP_APP"
    fi
}
trap cleanup EXIT

echo "==> Installing $DESTINATION_APP"
run_install_command mkdir -p "$INSTALL_DIR"
run_install_command rm -rf "$TEMP_APP" "$BACKUP_APP"
run_install_command /usr/bin/ditto --norsrc --noextattr "$SOURCE_APP" "$TEMP_APP"

# Stop only the installed client before replacing its bundle. User data lives
# outside the application bundle and is not touched.
pkill -x "SloppyClient" >/dev/null 2>&1 || true
pkill -x "SloppyClient-macOS" >/dev/null 2>&1 || true

if [[ -e "$DESTINATION_APP" ]]; then
    run_install_command mv "$DESTINATION_APP" "$BACKUP_APP"
fi
run_install_command mv "$TEMP_APP" "$DESTINATION_APP"
INSTALL_COMPLETE=1

if [[ $SHOULD_LAUNCH -eq 1 ]]; then
    echo "==> Launching SloppyClient"
    /usr/bin/open "$DESTINATION_APP"
fi

echo "Installed: $DESTINATION_APP"
