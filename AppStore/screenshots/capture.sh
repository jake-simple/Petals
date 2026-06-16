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

# Locale: SHOT_LANG=ko captures a Korean UI into captures/ko/ for the Korean
# App Store. Default (en) is unchanged — English UI into captures/.
SHOT_LANG="${SHOT_LANG:-en}"

APP="/tmp/petals-dd/Build/Products/Debug/Petals.app"
OUT="captures"
[ "$SHOT_LANG" = "ko" ] && OUT="captures/ko"
PROC="Petals.app/Contents/MacOS/Petals"
DOMAIN="com.idealapp.Petals"
BACKUP="/tmp/petals-prefs-backup.plist"

# Window capture helper (ScreenCaptureKit). It points at the window itself rather
# than screen coordinates, so it captures only the Petals window even when other
# apps sit on top. The swift interpreter can't initialize WindowServer (it would
# crash), so we always compile it to a binary.
CAPTURE_HELPER_SRC="lib/capture-window.swift"
CAPTURE_HELPER_BIN="lib/.capture-window.bin"

if [ ! -d "$APP" ]; then
  echo "ERROR: app not found at $APP — build it first:"
  echo "  xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -configuration Debug -derivedDataPath /tmp/petals-dd build"
  exit 1
fi

if [ ! -x "$CAPTURE_HELPER_BIN" ] || [ "$CAPTURE_HELPER_SRC" -nt "$CAPTURE_HELPER_BIN" ]; then
  echo "compiling capture-window helper"
  swiftc -O "$CAPTURE_HELPER_SRC" -o "$CAPTURE_HELPER_BIN"
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

# Optional filter: ./capture.sh 01-year  → recapture only that one.
ONLY="${1:-}"

capture() {
  local name="$1"; shift
  [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && return
  echo "→ $name"

  kill_all
  defaults delete "$DOMAIN" 2>/dev/null || true   # clean window geometry

  local envargs=(--env PETALS_SHOT=1 --env "PETALS_SHOT_LANG=$SHOT_LANG")
  local kv
  for kv in "$@"; do envargs+=(--env "$kv"); done

  # `open` is the reliable GUI launch; direct binary exec fails to make a window.
  # Force the App Store target locale so toolbar/month labels render in that language.
  local applang='(en)' applocale=en_US
  [ "$SHOT_LANG" = "ko" ] && applang='(ko)' && applocale=ko_KR
  open -n "${envargs[@]}" "$APP" --args -AppleLanguages "$applang" -AppleLocale "$applocale"

  local wid="" tries=0
  while [ "$tries" -lt 25 ]; do
    sleep 1
    wid=$(swift lib/winid.swift Petals 2>/dev/null || true)
    [ -n "$wid" ] && break
    tries=$((tries + 1))
  done
  sleep 2

  wid=$(swift lib/winid.swift Petals 2>/dev/null || true)
  if [ -z "$wid" ]; then
    echo "  !! window not found for $name"
    kill_all
    return
  fi

  osascript -e 'tell application "Petals" to activate' 2>/dev/null || true
  sleep 1

  # ScreenCaptureKit helper — captures the window directly, overlap-proof.
  if "$CAPTURE_HELPER_BIN" "$OUT/$name.png" Petals; then
    echo "  captured $OUT/$name.png"
  else
    # fallback: region capture by window bounds (wrong app may show if overlapped)
    echo "  !! SCK capture failed, falling back to bounds"
    local bounds
    bounds=$(osascript <<'EOF' 2>/dev/null || true
        tell application "System Events"
            tell process "Petals"
                if (count of windows) > 0 then
                    set p to position of window 1
                    set s to size of window 1
                    return (item 1 of p as string) & "," & (item 2 of p as string) & "," & (item 1 of s as string) & "," & (item 2 of s as string)
                end if
            end tell
        end tell
EOF
)
    if [ -n "$bounds" ] && [[ "$bounds" == *,*,*,* ]]; then
      echo "  bounds: $bounds"
      screencapture -x -R "$bounds" "$OUT/$name.png"
    else
      echo "  !! bounds unavailable, full screen"
      screencapture -x "$OUT/$name.png"
    fi
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
