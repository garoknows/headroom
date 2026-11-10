#!/bin/bash
# Lesson 18: one source of truth for the version. project.yml holds MARKETING_VERSION and
# CURRENT_PROJECT_VERSION; everything else must read them or match them.
#   scripts/check-version.sh                      # repo checks
#   scripts/check-version.sh v0.1.0               # also: the tag matches
#   scripts/check-version.sh v0.1.0 path/to.app   # also: the built app says the same
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-}"; APP="${2:-}"
FAIL=0
pass() { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=1; }
V="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
B="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
[ "$(grep -c 'MARKETING_VERSION:' "$ROOT/project.yml")" = 1 ] && [ -n "$V" ] && pass "project.yml: version $V" || bad "project.yml must set MARKETING_VERSION exactly once"
[ "$(grep -c 'CURRENT_PROJECT_VERSION:' "$ROOT/project.yml")" = 1 ] && [ -n "$B" ] && pass "project.yml: build $B" || bad "project.yml must set CURRENT_PROJECT_VERSION exactly once"
for p in App/Info.plist Widgets/Info.plist; do
  S=$(plutil -extract CFBundleShortVersionString raw "$ROOT/$p"); N=$(plutil -extract CFBundleVersion raw "$ROOT/$p")
  [ "$S" = '$(MARKETING_VERSION)' ] && [ "$N" = '$(CURRENT_PROJECT_VERSION)' ] && pass "$p reads the version from project.yml" || bad "$p has its own version ($S / $N)"
done
C=$(sed -n 's/^ *version "\(.*\)"/\1/p' "$ROOT/Casks/wiggleroom.rb")
[ "$C" = "$V" ] && pass "Casks/wiggleroom.rb: version $C" || bad "Cask version $C differs from $V"
grep -q "^# Wiggleroom $V\$" "$ROOT/docs/RELEASE_NOTES.md" && pass "docs/RELEASE_NOTES.md is for $V" || bad "docs/RELEASE_NOTES.md doesn't start with '# Wiggleroom $V'"
if [ -n "$TAG" ]; then
  [ "${TAG#v}" = "$V" ] && pass "Tag $TAG matches" || bad "Tag $TAG doesn't match project.yml version $V"
fi
if [ -n "$APP" ]; then
  for P in "$APP/Contents/Info.plist" "$APP/Contents/PlugIns/WiggleroomWidgets.appex/Contents/Info.plist"; do
    S=$(plutil -extract CFBundleShortVersionString raw "$P"); N=$(plutil -extract CFBundleVersion raw "$P")
    [ "$S" = "$V" ] && [ "$N" = "$B" ] && pass "$(basename "$(dirname "$(dirname "$P")")"): $S ($N)" || bad "$P says $S ($N), expected $V ($B)"
  done
fi
[ $FAIL = 0 ] && echo "Version checks passed." || echo "Version checks FAILED."
exit $FAIL
