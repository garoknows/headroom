#!/bin/bash
# Builds Headroom.app (app, widget extension and status line program) with swiftc directly,
# without Xcode's build system. The normal build is Xcode via project.yml (that's what CI and
# releases use); this script is for places where xcodebuild can't run, such as a sandboxed shell.
#
# It reads the version from project.yml (the only place it lives, lesson 18) and signs ad hoc
# unless SIGN_IDENTITY is set. Ad hoc builds have no App Group, so their widget can't get numbers.
#
# Usage: scripts/build-direct.sh
# Env:   HEADROOM_BUILD_DIR (default ~/Library/Caches/Headroom-build), ARCHS (default "arm64 x86_64"),
#        SIGN_IDENTITY (default "-", ad hoc)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
BUILD="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "Couldn't read the version from project.yml"; exit 1; }
B="${HEADROOM_BUILD_DIR:-$HOME/Library/Caches/Headroom-build}/direct-app"
APP="$B/Headroom.app"
IDENTITY="${SIGN_IDENTITY:--}"
DEV="$(xcode-select -p)"
TC="$DEV/Toolchains/XcodeDefault.xctoolchain"
SWIFTC="$TC/usr/bin/swiftc"; [ -x "$SWIFTC" ] || SWIFTC=swiftc
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export TMPDIR="$B/tmp"; mkdir -p "$TMPDIR"
P="$ROOT/Packages/HeadroomCore/Sources"

ARCHS="${ARCHS:-arm64 x86_64}"
APPS=(); TOOLS=(); EXTS=()
for ARCH in $ARCHS; do
  O="$B/$ARCH"; mkdir -p "$O"
  COMMON=(-swift-version 6 -O -whole-module-optimization -sdk "$SDK" -target "$ARCH-apple-macos14.0"
          -module-cache-path "$B/modcache" -plugin-path "$DEV/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
          -plugin-path "$TC/usr/lib/swift/host/plugins")
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name HeadroomCore \
    -emit-module-path "$O/HeadroomCore.swiftmodule" "$P"/HeadroomCore/*.swift -o "$O/libHeadroomCore.a"
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name HeadroomUI -I "$O" \
    -emit-module-path "$O/HeadroomUI.swiftmodule" "$P"/HeadroomUI/*.swift -o "$O/libHeadroomUI.a"
  "$SWIFTC" "${COMMON[@]}" -I "$O" -L "$O" -lHeadroomCore -module-name headroom_statusline \
    "$P"/headroom-statusline/main.swift -o "$O/headroom-statusline"
  "$SWIFTC" "${COMMON[@]}" -I "$O" -L "$O" -lHeadroomCore -lHeadroomUI -module-name Headroom \
    "$ROOT"/App/Sources/*.swift -o "$O/Headroom"
  "$SWIFTC" "${COMMON[@]}" -parse-as-library -application-extension -I "$O" -L "$O" -lHeadroomCore -lHeadroomUI \
    -module-name HeadroomWidgets "$ROOT"/Widgets/Sources/*.swift -o "$O/HeadroomWidgets"
  APPS+=("$O/Headroom"); TOOLS+=("$O/headroom-statusline"); EXTS+=("$O/HeadroomWidgets")
done

LIPO="$TC/usr/bin/lipo"; [ -x "$LIPO" ] || LIPO=lipo
rm -rf "$APP"
EXT="$APP/Contents/PlugIns/HeadroomWidgets.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
"$LIPO" -create "${APPS[@]}" -output "$APP/Contents/MacOS/Headroom"
"$LIPO" -create "${TOOLS[@]}" -output "$APP/Contents/MacOS/headroom-statusline"
"$LIPO" -create "${EXTS[@]}" -output "$EXT/Contents/MacOS/HeadroomWidgets"

# Info.plists with the build variables filled in (no App Group in this build).
fill() { sed -e "s/\$(EXECUTABLE_NAME)/$2/" -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$3/" -e "s/\$(PRODUCT_NAME)/$2/" \
             -e "s/\$(MARKETING_VERSION)/$VERSION/" -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" \
             -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/" -e "s/\$(HEADROOM_APP_GROUP)//" "$1"; }
fill "$ROOT/App/Info.plist" Headroom io.github.garoknows.headroom > "$APP/Contents/Info.plist"
fill "$ROOT/Widgets/Info.plist" HeadroomWidgets io.github.garoknows.headroom.widgets > "$EXT/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" "$EXT/Contents/Info.plist" >/dev/null
cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sign inside out: the helper, the widget (sandboxed), then the app. Hardened runtime everywhere.
SIGN=(--force --options runtime --timestamp=none --sign "$IDENTITY")
codesign "${SIGN[@]}" -i io.github.garoknows.headroom.statusline "$APP/Contents/MacOS/headroom-statusline"
codesign "${SIGN[@]}" --entitlements "$ROOT/Widgets/HeadroomWidgets.entitlements" "$EXT"
codesign "${SIGN[@]}" --entitlements "$ROOT/App/Headroom.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
