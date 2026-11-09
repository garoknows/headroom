#!/bin/bash
# Updates the Homebrew cask's version and sha256 lines, and nothing else
# (CI runs it on a copy and checks that only those two lines changed.)
# Usage: scripts/update-cask.sh Casks/headroom-usage.rb 0.1.0 <sha256 of the DMG>
# (Copied from Tracker for GitHub.)
set -euo pipefail
CASK="$1"; VERSION="$2"; SHA="$3"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "Not a version: $VERSION" >&2; exit 1; }
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "Not a sha256: $SHA" >&2; exit 1; }
[ "$(grep -cE '^  version "' "$CASK")" -eq 1 ] && [ "$(grep -cE '^  sha256 "' "$CASK")" -eq 1 ] \
  || { echo "Expected exactly one version and one sha256 line in $CASK" >&2; exit 1; }
TMP="$(mktemp "${TMPDIR:-/tmp}/cask.XXXXXX")"
sed -E "s/^  version \".*\"$/  version \"$VERSION\"/; s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" "$CASK" > "$TMP"
cat "$TMP" > "$CASK"
rm -f "$TMP"
grep -E '^  (version|sha256) ' "$CASK"
