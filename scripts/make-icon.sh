#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg, the icon's source
# drawing: scripts/render-icon.swift has AppKit draw the SVG at each size of an
# iconset, and iconutil packs them. Run it after editing the SVG and commit both
# files; scripts/build-app.sh copies the .icns into the app as it is.
#
# Usage: scripts/make-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
ICNS="$ROOT/Resources/AppIcon.icns"
ICONSET="$ROOT/build/AppIcon.iconset"

echo "==> Rendering $SVG"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/render-icon.swift" "$SVG" "$ICONSET"

iconutil --convert icns --output "$ICNS" "$ICONSET"
echo "$ICNS"
