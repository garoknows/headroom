#!/bin/bash
# Draws the app icon from code (WiggleroomMark in WiggleroomUI) and packs App/Resources/AppIcon.icns.
# Usage: tools/make-app-icon.sh   (run tools/render-docs.sh once first; it builds the renderer)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="${WIGGLEROOM_BUILD_DIR:-$HOME/Library/Caches/Wiggleroom-build}/render-docs"
SET="$B/AppIcon.iconset"
rm -rf "$SET"
"$B/render-docs" --iconset "$SET"
mkdir -p "$ROOT/App/Resources"
python3 "$ROOT/tools/strip-png-metadata.py" "$SET"/*.png
python3 "$ROOT/tools/make-icns.py" "$SET" "$ROOT/App/Resources/AppIcon.icns"
