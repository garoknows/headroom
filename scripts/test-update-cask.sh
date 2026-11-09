#!/bin/bash
# Checks that scripts/update-cask.sh changes only the version and sha256 lines of the cask,
# and refuses bad input.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/cask-test.XXXXXX")"
cp "$ROOT/Casks/headroom-usage.rb" "$T/c.rb"
SHA="$(printf 'x' | shasum -a 256 | cut -d' ' -f1)"
"$ROOT/scripts/update-cask.sh" "$T/c.rb" 9.8.7 "$SHA" >/dev/null
CHANGED="$( { diff "$ROOT/Casks/headroom-usage.rb" "$T/c.rb" || true; } | grep -E '^[<>]' | wc -l | tr -d ' ')"
[ "$CHANGED" = 4 ] || { echo "FAIL: expected 2 lines changed, diff has $CHANGED changed lines"; exit 1; }
grep -q '^  version "9.8.7"$' "$T/c.rb" && grep -q "^  sha256 \"$SHA\"\$" "$T/c.rb" || { echo "FAIL: values not written"; exit 1; }
if "$ROOT/scripts/update-cask.sh" "$T/c.rb" 'bad version' "$SHA" 2>/dev/null; then echo "FAIL: accepted a bad version"; exit 1; fi
if "$ROOT/scripts/update-cask.sh" "$T/c.rb" 1.0.0 'nothex' 2>/dev/null; then echo "FAIL: accepted a bad sha256"; exit 1; fi
rm -rf "$T"
echo "update-cask.sh: ok"
