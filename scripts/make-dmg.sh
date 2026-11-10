#!/bin/bash
# Packages Wiggleroom.app into a .dmg with an Applications shortcut, using macOS's hdiutil.
# (Adapted from Tallshot.) Runs on GitHub's Mac runner; hdiutil can't run in a sandboxed shell.
# Usage: scripts/make-dmg.sh path/to/Wiggleroom.app path/to/Wiggleroom-0.1.0.dmg
set -euo pipefail
APP="$1"; OUT="$2"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/wiggleroom-dmg.XXXXXX")"
ditto "$APP" "$STAGE/Wiggleroom.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Wiggleroom" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"
echo "Wrote $OUT"
