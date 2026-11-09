#!/bin/bash
# Renders the widget states and setup pictures to PNG (docs/images by default) with swiftc,
# using the real HeadroomCore and HeadroomUI code.
# Usage: tools/render-docs.sh [output folder]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/images}"
B="${HEADROOM_BUILD_DIR:-$HOME/Library/Caches/Headroom-build}/render-docs"
mkdir -p "$B"
DEV="$(xcode-select -p)"
TC="$DEV/Toolchains/XcodeDefault.xctoolchain"
SWIFTC="$TC/usr/bin/swiftc"; [ -x "$SWIFTC" ] || SWIFTC=swiftc
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export TMPDIR="$B/tmp"; mkdir -p "$TMPDIR"
COMMON=(-swift-version 6 -sdk "$SDK" -module-cache-path "$B/modcache" -target "$(uname -m)-apple-macos14.0"
        -plugin-path "$TC/usr/lib/swift/host/plugins")
P="$ROOT/Packages/HeadroomCore/Sources"
"$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name HeadroomCore \
  -emit-module-path "$B/HeadroomCore.swiftmodule" "$P"/HeadroomCore/*.swift -o "$B/libHeadroomCore.a"
"$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name HeadroomUI -I "$B" \
  -emit-module-path "$B/HeadroomUI.swiftmodule" "$P"/HeadroomUI/*.swift -o "$B/libHeadroomUI.a"
"$SWIFTC" "${COMMON[@]}" -I "$B" -L "$B" -lHeadroomCore -lHeadroomUI -module-name RenderDocs \
  "$ROOT"/tools/RenderDocs/main.swift -o "$B/render-docs"
mkdir -p "$OUT"
"$B/render-docs" "$OUT"
# The PNG encoder adds an EXIF block; pictures must carry no metadata (lesson 4).
python3 "$ROOT/tools/strip-png-metadata.py" "$OUT"/*.png
python3 "$ROOT/scripts/check-image-metadata.py" "$OUT"
