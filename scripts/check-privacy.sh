#!/bin/bash
# Checks Headroom's privacy and safety rules in the source and, if given, in a built app.
#   scripts/check-privacy.sh                        # source checks
#   scripts/check-privacy.sh path/to/Headroom.app   # source + built app checks
# Exit code 0 means every rule held. (Adapted from Tallshot's check.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
FAIL=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=1; }
CORE="$ROOT/Packages/HeadroomCore/Sources"
SRC=("$ROOT/App/Sources" "$ROOT/Widgets/Sources" "$CORE")
# Text is checked with `grep -q ... <<< "$X"`, never `echo "$X" | grep -q`: with pipefail, grep
# quitting at its match can kill the writer, and that reads as "no match" (a false pass).

echo "Entitlements"
for f in App/Headroom.entitlements App/Headroom-Signed.entitlements Widgets/HeadroomWidgets.entitlements Widgets/HeadroomWidgets-Signed.entitlements; do
  KEYS=$(plutil -convert json -o - "$ROOT/$f" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True, separators=(",", ":")))')
  case "$f" in
    App/Headroom.entitlements) WANT='{}' ;;
    App/Headroom-Signed.entitlements) WANT='{"com.apple.security.application-groups":["$(HEADROOM_APP_GROUP)"]}' ;;
    Widgets/HeadroomWidgets.entitlements) WANT='{"com.apple.security.app-sandbox":true}' ;;
    *) WANT='{"com.apple.security.app-sandbox":true,"com.apple.security.application-groups":["$(HEADROOM_APP_GROUP)"]}' ;;  # keys sorted
  esac
  [ "$KEYS" = "$WANT" ] && pass "$f: exactly what it needs ($WANT)" || bad "$f has $KEYS, expected $WANT"
done

echo "Source code"
NET='URLSession|NSURLConnection|URLRequest|import Network|CFSocket|NWConnection|NWPathMonitor|NWListener|WebSocket|socket\(|CFStream|getaddrinfo|WKWebView|import WebKit|HTTPCookie'
if grep -rn -E "$NET" "${SRC[@]}" >/dev/null; then bad "Network code found:"; grep -rn -E "$NET" "${SRC[@]}"
else pass "No network code"; fi
CRED='SecItem|SecKeychain|Claude Code-credentials|api\.anthropic\.com|claude\.ai/api|[Oo][Aa]uth|access_token|refresh_token|Cookies\.binarycookies'
if grep -rn -E "$CRED" "${SRC[@]}" >/dev/null; then bad "Keychain, token or claude.ai access found:"; grep -rn -E "$CRED" "${SRC[@]}"
else pass "No Keychain, tokens, cookies or Anthropic endpoints"; fi
WIDGET_BAD='HeadroomPaths|usageFile|claudeSettings|homeDirectory|NSHomeDirectory|"~/|Application Support'
if grep -rn -E "$WIDGET_BAD" "$ROOT/Widgets/Sources" >/dev/null; then bad "Widget reads something besides the App Group snapshot (lesson 10):"; grep -rn -E "$WIDGET_BAD" "$ROOT/Widgets/Sources"
else pass "Widget reads only the App Group snapshot (lesson 10)"; fi
APPLY=$(grep -rln 'ClaudeSettingsEditor.apply' "${SRC[@]}")
[ "$APPLY" = "$CORE/HeadroomCore/Connection.swift" ] && pass "Claude Code settings are changed only through Connection (connect/disconnect)" \
  || bad "ClaudeSettingsEditor.apply used outside Connection.swift: $APPLY"
CALLS=$(grep -rn -E '\.(connect|disconnect)\(\)' "$ROOT/App/Sources" | sed -E "s|^$ROOT/||; s/:[0-9]+:/: /" | sed -E 's/ +/ /g')
# The three button actions, the two AppModel methods they call, Delete All Data, and --disconnect.
WANT_CALLS=$(printf '%s\n' \
  'App/Sources/SetupView.swift: Button("Connect to Claude Code") { model.connect() }.buttonStyle(.borderedProminent)' \
  "App/Sources/SettingsView.swift: model.connect()" \
  'App/Sources/SettingsView.swift: Button("Disconnect") { model.disconnect() }' \
  "App/Sources/AppModel.swift: report(connectionHelper.connect())" \
  "App/Sources/AppModel.swift: report(connectionHelper.disconnect())" \
  "App/Sources/AppModel.swift: switch connectionHelper.disconnect() {" \
  "App/Sources/main.swift: switch connection.disconnect() {")
if [ "$(sort <<< "$CALLS")" = "$(sort <<< "$WANT_CALLS")" ]; then
  pass "Connect/disconnect run only from the Connect and Disconnect buttons, Delete All Data, and --disconnect"
else bad "Connect/disconnect called from somewhere unexpected:"; echo "$CALLS"; fi
PROCS=$(grep -rn -E 'Process\(|posix_spawn\(|NSTask|(^|[^.A-Za-z_])system\(|popen\(' "${SRC[@]}")
if [ "$(grep -c . <<< "$PROCS")" = 1 ] && grep -q 'headroom-statusline/main.swift:.*posix_spawn(&pid, "/bin/sh"' <<< "$PROCS"; then
  pass "Starts one program only: the user's previous status line, from the status line helper"
else bad "Starts other programs:"; echo "$PROCS"; fi
if grep -n -E 'print\(|FileHandle\.standardOutput|fputs|NSLog|os_log|Logger\(' "$CORE/headroom-statusline/main.swift" >/dev/null; then
  bad "The status line helper writes its own output (the user's status line must look unchanged)"
else pass "The status line helper prints nothing of its own"; fi
if grep -rn -E 'os_log|Logger\(|NSLog|debugPrint\(|dump\(' "${SRC[@]}" >/dev/null; then bad "Logging found:"; grep -rn -E 'os_log|Logger\(|NSLog|debugPrint\(|dump\(' "${SRC[@]}"
else pass "No logging"; fi
WRITES=$(grep -rn -E '\.write\(to|\.write\(toFile|createFile\(|FileHandle\(forWriting|fopen\(' "${SRC[@]}")
[ -z "$WRITES" ] && pass "Files are written only through SecureFile (private, all-or-nothing)" || { bad "Other file writes:"; echo "$WRITES"; }
if grep -n -E '\.package\(' "$ROOT/Packages/HeadroomCore/Package.swift" >/dev/null || grep -n -E '^\s+url:' "$ROOT/project.yml" >/dev/null; then
  bad "Third-party package dependency found"
else pass "No third-party packages"; fi
if grep -rn -i -E 'analytics|telemetry|crashlytics|sentry|sparkle|firebase|mixpanel' "${SRC[@]}" >/dev/null; then
  bad "Analytics, crash reporting or updater code found"
else pass "No analytics, crash reporting or auto-updater"; fi

if [ -n "$APP" ]; then
  echo "Built app ($APP)"
  W="$APP/Contents/PlugIns/HeadroomWidgets.appex"
  H="$APP/Contents/MacOS/headroom-statusline"
  [ -x "$H" ] && pass "Status line helper is inside the app (Contents/MacOS)" || bad "headroom-statusline missing from Contents/MacOS"
  [ -d "$W" ] && pass "Widget extension is inside the app" || bad "Widget extension missing"
  for B in "$APP" "$W" "$H"; do
    SIG=$(codesign -dv "$B" 2>&1); grep -q "flags=.*runtime" <<< "$SIG" && pass "Hardened runtime on: $(basename "$B")" || bad "Hardened runtime off: $(basename "$B")"
  done
  WE=$(codesign -d --entitlements :- "$W" 2>/dev/null)
  grep -q "com.apple.security.app-sandbox" <<< "$WE" && pass "Widget is sandboxed" || bad "Widget is not sandboxed"
  AE=$(codesign -d --entitlements :- "$APP" 2>/dev/null)
  grep -q -E "network\.(client|server)" <<< "$AE$WE" && bad "Network entitlement in a signature" || pass "No network entitlement in any signature"
  for BIN in "$APP/Contents/MacOS/Headroom" "$W/Contents/MacOS/HeadroomWidgets" "$H"; do
    LIBS=$(otool -L "$BIN" 2>/dev/null | grep -v -E ':$' | awk '{print $1}' | grep -v -E '^/System/Library/|^/usr/lib/' || true)
    [ -z "$LIBS" ] && pass "$(basename "$BIN") links only Apple system libraries" || bad "$(basename "$BIN") links non-system libraries: $LIBS"
    SYMS=$(nm -u "$BIN" 2>/dev/null)
    grep -q -E 'URLSession|NSURLConnection|_connect$|_socket$|nw_connection|CFSocket|getaddrinfo|SecItemCopyMatching' <<< "$SYMS" \
      && bad "$(basename "$BIN") references network or Keychain symbols" || pass "$(basename "$BIN") references no network or Keychain symbols"
  done
fi

[ $FAIL = 0 ] && echo "All privacy checks passed." || echo "Privacy checks FAILED."
exit $FAIL
