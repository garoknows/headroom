#!/bin/bash
# Draws the app icon from code (HeadroomMark in HeadroomUI) and packs App/Resources/AppIcon.icns.
# Usage: tools/make-app-icon.sh   (run tools/render-docs.sh once first; it builds the renderer)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="${HEADROOM_BUILD_DIR:-$HOME/Library/Caches/Headroom-build}/render-docs"
SET="$B/AppIcon.iconset"
rm -rf "$SET"
"$B/render-docs" --iconset "$SET"
mkdir -p "$ROOT/App/Resources"
python3 "$ROOT/tools/strip-png-metadata.py" "$SET"/*.png
python3 "$ROOT/tools/make-icns.py" "$SET" "$ROOT/App/Resources/AppIcon.icns"
