#!/bin/bash
# Generates app icon PNGs from AppIcon.svg using rsvg-convert.
# Usage: ./scripts/make_icon.sh
# Requires: brew install librsvg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="$SCRIPT_DIR/../OralScribe/Resources/AppIcon.svg"
ICONSET="$SCRIPT_DIR/../OralScribe/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert &>/dev/null; then
    echo "rsvg-convert not found. Install with: brew install librsvg"
    exit 1
fi

for SIZE in 16 32 64 128 256 512 1024; do
    echo "  ${SIZE}x${SIZE}"
    rsvg-convert -w "$SIZE" -h "$SIZE" "$SVG" > "$ICONSET/icon_${SIZE}x${SIZE}.png"
done

echo "Done."
