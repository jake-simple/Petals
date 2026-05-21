#!/usr/bin/env bash
# Render the 5 Petals App Store screenshots to PNG (2880x1800, Mac App Store standard).
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

for f in 01-year 02-themes 03-zoom 04-whiteboard 05-mac; do
  "$CHROME" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=2 \
    --window-size=1440,900 \
    --virtual-time-budget=4000 \
    --default-background-color=00000000 \
    --screenshot="$f.png" \
    "file://$PWD/$f.html" >/dev/null 2>&1
  echo "rendered $f.png"
done

echo "Done. 5 screenshots at 2880x1800."
