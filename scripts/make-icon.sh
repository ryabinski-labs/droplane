#!/bin/bash
# Renders Resources/AppIcon.svg into the macOS .icns used by the app bundle.
# Requires librsvg (brew install librsvg) and Xcode command line tools (iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="Resources/AppIcon.svg"
ICONSET="build/AppIcon.iconset"
ICNS="Resources/AppIcon.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "error: rsvg-convert is required (brew install librsvg)" >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
    rsvg-convert -w "$1" -h "$1" "$SOURCE" -o "$ICONSET/$2"
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Wrote $ICNS"
