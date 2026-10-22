#!/usr/bin/env bash
# Zips build/Notch.app into build/dist/Notch-<version>.zip for sharing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Notch.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DIST="$ROOT/build/dist"
ZIP="$DIST/Notch-$VERSION.zip"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found; run scripts/build-app.sh first" >&2
    exit 1
fi

mkdir -p "$DIST"
rm -f "$ZIP"
# ditto keeps the bundle structure, symlinks, and code signature intact.
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$ZIP"
