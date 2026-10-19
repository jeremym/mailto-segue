#!/usr/bin/env bash
#
# Assemble build/Segue.app from the SwiftPM products and sign it.
#
#   scripts/bundle.sh [--universal] [--identity NAME] [--build N] [--configuration release|debug]
#
# Env alternatives: UNIVERSAL=1, CODESIGN_IDENTITY (default "-" = ad-hoc),
# BUILD_NUMBER (default 1). Output: build/Segue.app (+ build/segue symlink).
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL="${UNIVERSAL:-0}"
IDENTITY="${CODESIGN_IDENTITY:--}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIG="release"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal) UNIVERSAL=1; shift ;;
        --identity) IDENTITY="$2"; shift 2 ;;
        --build) BUILD_NUMBER="$2"; shift 2 ;;
        --configuration) CONFIG="$2"; shift 2 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

step() { printf '\n==> %s\n' "$1"; }

VERSION="$(sed -nE 's/.*static let string = "([^"]+)".*/\1/p' Sources/SegueCore/Version.swift)"
[[ -n "$VERSION" ]] || { echo "error: could not read version from Sources/SegueCore/Version.swift" >&2; exit 1; }

ARCH_FLAGS=""
if [[ "$UNIVERSAL" == "1" ]]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

step "Building Segue $VERSION ($CONFIG$([[ "$UNIVERSAL" == 1 ]] && echo ', universal'))"
# shellcheck disable=SC2086  # ARCH_FLAGS is intentionally word-split
swift build -c "$CONFIG" $ARCH_FLAGS
BIN_DIR="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)"

APP="build/Segue.app"
step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN_DIR/Segue" "$APP/Contents/MacOS/Segue"
# The CLI lives in Helpers/, not MacOS/: "Segue" and "segue" would be the same
# file on a case-insensitive filesystem.
cp "$BIN_DIR/segue-cli" "$APP/Contents/Helpers/segue"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -d Resources/ServiceIcons ]]; then
    cp -R Resources/ServiceIcons "$APP/Contents/Resources/ServiceIcons"
fi
ln -sf "Segue.app/Contents/Helpers/segue" build/segue

step "Signing with identity '$IDENTITY'"
# Nested code first, then the bundle (--deep is deprecated).
codesign --force --sign "$IDENTITY" --identifier "com.overtonefoundry.segue.cli" "$APP/Contents/Helpers/segue"
codesign --force --sign "$IDENTITY" --identifier "com.overtonefoundry.segue" "$APP"
codesign --verify --strict "$APP"

step "Done: $APP ($(du -sh "$APP" | cut -f1))"
