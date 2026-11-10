#!/bin/bash
# Renders the widget states and setup pictures to PNG (docs/images by default) with swiftc,
# using the real WiggleroomCore and WiggleroomUI code.
# Usage: tools/render-docs.sh [output folder]
#        tools/render-docs.sh --windows <folder>   (every window and popover state, for checking by eye)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/images}"
B="${WIGGLEROOM_BUILD_DIR:-$HOME/Library/Caches/Wiggleroom-build}/render-docs"
mkdir -p "$B"
DEV="$(xcode-select -p)"
TC="$DEV/Toolchains/XcodeDefault.xctoolchain"
SWIFTC="$TC/usr/bin/swiftc"; [ -x "$SWIFTC" ] || SWIFTC=swiftc
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export TMPDIR="$B/tmp"; mkdir -p "$TMPDIR"
COMMON=(-swift-version 6 -sdk "$SDK" -module-cache-path "$B/modcache" -target "$(uname -m)-apple-macos14.0"
        -plugin-path "$DEV/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" -plugin-path "$TC/usr/lib/swift/host/plugins")
P="$ROOT/Packages/WiggleroomCore/Sources"
"$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name WiggleroomCore \
  -emit-module-path "$B/WiggleroomCore.swiftmodule" "$P"/WiggleroomCore/*.swift -o "$B/libWiggleroomCore.a"
"$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name WiggleroomUI -I "$B" \
  -emit-module-path "$B/WiggleroomUI.swiftmodule" "$P"/WiggleroomUI/*.swift -o "$B/libWiggleroomUI.a"
"$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name WiggleroomWindows -I "$B" \
  -emit-module-path "$B/WiggleroomWindows.swiftmodule" "$P"/WiggleroomWindows/*.swift -o "$B/libWiggleroomWindows.a"
"$SWIFTC" "${COMMON[@]}" -I "$B" -L "$B" -lWiggleroomCore -lWiggleroomUI -lWiggleroomWindows -module-name RenderDocs \
  "$ROOT"/tools/RenderDocs/main.swift -o "$B/render-docs"
if [ "${1:-}" = "--windows" ]; then
  OUT="$2"; mkdir -p "$OUT"
  "$B/render-docs" --windows "$OUT"
else
  mkdir -p "$OUT"
  "$B/render-docs" "$OUT"
fi
# The PNG encoder adds an EXIF block; pictures must carry no metadata (lesson 4).
python3 "$ROOT/tools/strip-png-metadata.py" "$OUT"/*.png
python3 "$ROOT/scripts/check-image-metadata.py" "$OUT"
