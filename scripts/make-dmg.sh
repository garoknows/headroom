#!/bin/bash
# Packages Headroom.app into a .dmg with an Applications shortcut, using macOS's hdiutil.
# (Adapted from Tallshot.) Runs on GitHub's Mac runner; hdiutil can't run in a sandboxed shell.
# Usage: scripts/make-dmg.sh path/to/Headroom.app path/to/Headroom-0.1.0.dmg
set -euo pipefail
APP="$1"; OUT="$2"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/headroom-dmg.XXXXXX")"
ditto "$APP" "$STAGE/Headroom.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Headroom" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"
echo "Wrote $OUT"
