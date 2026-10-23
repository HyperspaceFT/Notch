#!/usr/bin/env bash
# Builds the Swift package and assembles a signed build/Notch.app: with the local
# certificate from scripts/create-signing-cert.sh when it is in the keychain,
# ad hoc otherwise.
#
# Usage: scripts/build-app.sh [debug|release]   (default: release)
# Env:   BUILD_NUMBER overrides CFBundleVersion (default: git commit count, else 1).
#        SIGN_IDENTITY overrides the certificate name (default: Notch Local Signing).
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

# The MediaRemote adapter the Now Playing feature runs through /usr/bin/perl to read what
# any app (a browser tab included) plays. Keep its original signature: it is not re-signed.
ADAPTER="$ROOT/Vendor/MediaRemoteAdapter"
mkdir -p "$APP/Contents/Frameworks"
ditto --noextattr --noqtn "$ADAPTER/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$ADAPTER/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
cp "$ADAPTER/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE"

# An ad-hoc signature changes with every build, and macOS then treats the app as
# new and drops its Accessibility access; a certificate's signature stays the same.
# Listed without -v: the self-signed certificate is untrusted, which signing allows.
SIGN_IDENTITY="${SIGN_IDENTITY:-Notch Local Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$SIGN_IDENTITY\""; then
    echo "==> Signing ($SIGN_IDENTITY)"
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
    echo "==> Signing (ad-hoc; run 'make cert' to keep Accessibility access across builds)"
    codesign --force --sign - "$APP"
fi
codesign --verify --verbose "$APP"

echo "$APP"
