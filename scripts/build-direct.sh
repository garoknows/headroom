#!/bin/bash
# Builds Wiggleroom.app (app, widget extension and status line program) with swiftc directly,
# without Xcode's build system. The normal build is Xcode via project.yml (that's what CI and
# releases use); this script is for places where xcodebuild can't run, such as a sandboxed shell.
#
# It reads the version from project.yml (the only place it lives, lesson 18) and signs ad hoc
# unless SIGN_IDENTITY is set. Ad hoc builds have no App Group, so their widget can't get numbers.
#
# Usage: scripts/build-direct.sh
# Env:   WIGGLEROOM_BUILD_DIR (default ~/Library/Caches/Wiggleroom-build), ARCHS (default "arm64 x86_64"),
#        SIGN_IDENTITY (default "-", ad hoc)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
BUILD="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "Couldn't read the version from project.yml"; exit 1; }
B="${WIGGLEROOM_BUILD_DIR:-$HOME/Library/Caches/Wiggleroom-build}/direct-app"
APP="$B/Wiggleroom.app"
IDENTITY="${SIGN_IDENTITY:--}"
DEV="$(xcode-select -p)"
TC="$DEV/Toolchains/XcodeDefault.xctoolchain"
SWIFTC="$TC/usr/bin/swiftc"; [ -x "$SWIFTC" ] || SWIFTC=swiftc
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export TMPDIR="$B/tmp"; mkdir -p "$TMPDIR"
P="$ROOT/Packages/WiggleroomCore/Sources"

ARCHS="${ARCHS:-arm64 x86_64}"
APPS=(); TOOLS=(); EXTS=()
for ARCH in $ARCHS; do
  O="$B/$ARCH"; mkdir -p "$O"
  COMMON=(-swift-version 6 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macos14.0"
          -module-cache-path "$B/modcache" -plugin-path "$DEV/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
          -plugin-path "$TC/usr/lib/swift/host/plugins")
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name WiggleroomCore \
    -emit-module-path "$O/WiggleroomCore.swiftmodule" "$P"/WiggleroomCore/*.swift -o "$O/libWiggleroomCore.a"
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name WiggleroomUI -I "$O" \
    -emit-module-path "$O/WiggleroomUI.swiftmodule" "$P"/WiggleroomUI/*.swift -o "$O/libWiggleroomUI.a"
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name WiggleroomWindows -I "$O" \
    -emit-module-path "$O/WiggleroomWindows.swiftmodule" "$P"/WiggleroomWindows/*.swift -o "$O/libWiggleroomWindows.a"
  "$SWIFTC" "${COMMON[@]}" -I "$O" -L "$O" -lWiggleroomCore -module-name wiggleroom_statusline \
    "$P"/wiggleroom-statusline/main.swift -o "$O/wiggleroom-statusline"
  "$SWIFTC" "${COMMON[@]}" -I "$O" -L "$O" -lWiggleroomCore -lWiggleroomUI -lWiggleroomWindows -module-name Wiggleroom \
    "$ROOT"/App/Sources/*.swift -o "$O/Wiggleroom"
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -application-extension -I "$O" -L "$O" -lWiggleroomCore -lWiggleroomUI \
    -module-name WiggleroomWidgets "$ROOT"/Widgets/Sources/*.swift -o "$O/WiggleroomWidgets"
  APPS+=("$O/Wiggleroom"); TOOLS+=("$O/wiggleroom-statusline"); EXTS+=("$O/WiggleroomWidgets")
done

LIPO="$TC/usr/bin/lipo"; [ -x "$LIPO" ] || LIPO=lipo
rm -rf "$APP"
EXT="$APP/Contents/PlugIns/WiggleroomWidgets.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
"$LIPO" -create "${APPS[@]}" -output "$APP/Contents/MacOS/Wiggleroom"
"$LIPO" -create "${TOOLS[@]}" -output "$APP/Contents/MacOS/wiggleroom-statusline"
"$LIPO" -create "${EXTS[@]}" -output "$EXT/Contents/MacOS/WiggleroomWidgets"

# Info.plists with the build variables filled in (no App Group in this build).
fill() { sed -e "s/\$(EXECUTABLE_NAME)/$2/" -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$3/" -e "s/\$(PRODUCT_NAME)/$2/" \
             -e "s/\$(MARKETING_VERSION)/$VERSION/" -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" \
             -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/" -e "s/\$(WIGGLEROOM_APP_GROUP)//" "$1"; }
fill "$ROOT/App/Info.plist" Wiggleroom io.github.garoknows.wiggleroom > "$APP/Contents/Info.plist"
fill "$ROOT/Widgets/Info.plist" WiggleroomWidgets io.github.garoknows.wiggleroom.widgets > "$EXT/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" "$EXT/Contents/Info.plist" >/dev/null
cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sign inside out: the helper, the widget (sandboxed), then the app. Hardened runtime everywhere.
SIGN=(--force --options runtime --timestamp=none --sign "$IDENTITY")
codesign "${SIGN[@]}" -i io.github.garoknows.wiggleroom.statusline "$APP/Contents/MacOS/wiggleroom-statusline"
codesign "${SIGN[@]}" --entitlements "$ROOT/Widgets/WiggleroomWidgets.entitlements" "$EXT"
codesign "${SIGN[@]}" --entitlements "$ROOT/App/Wiggleroom.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
