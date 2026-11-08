#!/bin/bash
# Builds and runs the HeadroomCore tests with swiftc directly, without SwiftPM or Xcode's
# build system. Useful where those can't write their temp files (a sandboxed shell).
# Normal use: `swift test --package-path Packages/HeadroomCore` (that's what CI runs).
#
# Usage: Packages/HeadroomCore/run-tests-direct.sh [extra arguments for the test runner]
# Env:   HEADROOM_BUILD_DIR (default ~/Library/Caches/Headroom-build)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
B="${HEADROOM_BUILD_DIR:-$HOME/Library/Caches/Headroom-build}/direct-tests"
mkdir -p "$B"
DEV="$(xcode-select -p)"
PLAT="$DEV/Platforms/MacOSX.platform/Developer"
TC="$DEV/Toolchains/XcodeDefault.xctoolchain"
SWIFTC="$TC/usr/bin/swiftc"; [ -x "$SWIFTC" ] || SWIFTC=swiftc
SDK="$PLAT/SDKs/MacOSX.sdk"
export TMPDIR="$B/tmp"; mkdir -p "$TMPDIR"
COMMON=(-swift-version 6 -sdk "$SDK" -module-cache-path "$B/modcache" -target "$(uname -m)-apple-macos14.0"
        -F "$PLAT/Library/Frameworks" -I "$PLAT/usr/lib" -L "$PLAT/usr/lib"
        -plugin-path "$TC/usr/lib/swift/host/plugins/testing" -plugin-path "$TC/usr/lib/swift/host/plugins")

# The library, built for testing.
"$SWIFTC" "${COMMON[@]}" -Onone -parse-as-library -enable-testing -emit-library -static -emit-module -module-name HeadroomCore \
  -emit-module-path "$B/HeadroomCore.swiftmodule" "$HERE"/Sources/HeadroomCore/*.swift -o "$B/libHeadroomCore.a"

# The real command, built the way it ships (optimized), for the end-to-end tests.
"$SWIFTC" "${COMMON[@]}" -O -I "$B" -L "$B" -lHeadroomCore -module-name headroom_statusline \
  "$HERE"/Sources/headroom-statusline/main.swift -o "$B/headroom-statusline"

cat > "$B/runner.swift" <<'SWIFT'
import Foundation
import Testing
@main struct Runner { static func main() async { exit(await Testing.__swiftPMEntryPoint()) } }
SWIFT
"$SWIFTC" "${COMMON[@]}" -Onone -parse-as-library -I "$B" -L "$B" -lHeadroomCore -module-name HeadroomCoreTests \
  -Xlinker -rpath -Xlinker "$PLAT/Library/Frameworks" -Xlinker -rpath -Xlinker "$PLAT/usr/lib" \
  "$HERE"/Tests/HeadroomCoreTests/*.swift "$HERE"/Tests/StatuslineTests/*.swift "$B/runner.swift" -o "$B/headroom-core-tests"
HEADROOM_TEST_TMP="$TMPDIR" HEADROOM_STATUSLINE_BIN="$B/headroom-statusline" "$B/headroom-core-tests" "$@"
