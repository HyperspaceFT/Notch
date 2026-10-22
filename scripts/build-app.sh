#!/usr/bin/env bash
# Builds the Swift package and assembles an ad-hoc signed build/Notch.app.
#
# Usage: scripts/build-app.sh [debug|release]   (default: release)
# Env:   BUILD_NUMBER overrides CFBundleVersion (default: git commit count, else 1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
case "$CONFIG" in
    debug|release) ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 64 ;;
esac

APP_NAME="Notch"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"

echo "==> swift build -c $CONFIG ($VERSION, build $BUILD_NUMBER)"
swift build --package-path "$ROOT" -c "$CONFIG" --arch arm64 --product "$APP_NAME"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --arch arm64 --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: executable not found at $EXECUTABLE" >&2
    exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

echo "$APP"
