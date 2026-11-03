#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/petals-regression.XXXXXX")
trap 'rm -rf "$build"' EXIT
src="$repo/Petals/Petals"
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
  "$src/Helpers/CalendarLayout.swift" "$src/Helpers/WindowInputScope.swift" \
  "$src/EventKit/EventLayoutEngine.swift" \
  "$src/Models/CanvasItemType.swift" "$src/Models/CanvasItem.swift" \
  "$src/Models/YearDocument.swift" "$src/Models/VisionBoard.swift" \
  "$src/Models/VisionBoardItem.swift" "$src/Models/CanvasItemSnapshot.swift" \
  "$repo/Tests/PetalsRegression.swift" -o "$build/regression"
for zone in Asia/Seoul America/Los_Angeles UTC; do
  echo "Timezone: $zone"
  TZ="$zone" "$build/regression"
done
