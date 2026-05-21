#!/usr/bin/env bash
# Launch Petals in screenshot mode (5 states) and capture each window to captures/.
#
# Window geometry: the app's saved window-frame prefs can be stale/off-screen
# and hijack captures. We back up the whole prefs domain, clear it so each
# launch starts clean, then restore it — the user's real settings are untouched.
#
# Requires: app built at the path below; Screen Recording permission for the
# terminal running this script (macOS prompts once on first capture).
set -uo pipefail
cd "$(dirname "$0")"

APP="/tmp/petals-dd/Build/Products/Debug/Petals.app"
OUT="captures"
PROC="Petals.app/Contents/MacOS/Petals"
DOMAIN="com.idealapp.Petals"
BACKUP="/tmp/petals-prefs-backup.plist"

if [ ! -d "$APP" ]; then
  echo "ERROR: app not found at $APP — build it first:"
  echo "  xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -configuration Debug -derivedDataPath /tmp/petals-dd build"
  exit 1
fi

mkdir -p "$OUT"

kill_all() {
  pkill -f "$PROC" 2>/dev/null || true
  for _ in $(seq 1 16); do
    pgrep -f "$PROC" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  pkill -9 -f "$PROC" 2>/dev/null || true
  sleep 1
}

defaults export "$DOMAIN" "$BACKUP" 2>/dev/null || true
restore_prefs() {
  [ -f "$BACKUP" ] && defaults import "$DOMAIN" "$BACKUP" 2>/dev/null && echo "restored $DOMAIN prefs"
}
trap 'kill_all; restore_prefs' EXIT

capture() {
  local name="$1"; shift
  echo "→ $name"

  kill_all
  defaults delete "$DOMAIN" 2>/dev/null || true   # clean window geometry

  local envargs=(--env PETALS_SHOT=1)
  local kv
  for kv in "$@"; do envargs+=(--env "$kv"); done

  # `open` is the reliable GUI launch; direct binary exec fails to make a window.
  open -n "${envargs[@]}" "$APP" --args -AppleLanguages '(en)' -AppleLocale en_US

  local wid="" tries=0
  while [ "$tries" -lt 25 ]; do
    sleep 1
    wid=$(swift lib/winid.swift Petals 2>/dev/null || true)
    [ -n "$wid" ] && break
    tries=$((tries + 1))
  done
  sleep 2

  wid=$(swift lib/winid.swift Petals 2>/dev/null || true)
  if [ -n "$wid" ]; then
    screencapture -x -o -l"$wid" "$OUT/$name.png"
    if [ -f "$OUT/$name.png" ]; then
      echo "  captured $OUT/$name.png"
    else
      echo "  !! screencapture failed (Screen Recording permission?)"
    fi
  else
    echo "  !! window not found for $name"
  fi

  kill_all
}

capture 01-year
capture 02-themes     PETALS_SHOT_THEME=tokyo-night
capture 03-zoom       PETALS_SHOT_ZOOM=3
capture 04-whiteboard PETALS_SHOT_MODE=whiteboard
capture 05-mac        PETALS_SHOT_THEME=classic

echo ""
echo "Done. Raw window captures in $OUT/"
echo "If captures are black/empty, grant Screen Recording permission to your"
echo "terminal (System Settings > Privacy & Security > Screen Recording) and re-run."
