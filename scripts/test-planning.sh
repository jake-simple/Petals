#!/bin/bash
set -euo pipefail
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/petals-planning.XXXXXX")
trap 'rm -rf "$build"' EXIT
src="$repo/Petals/Petals"
cd "$repo"
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor)
models=("$src/Models/CanvasItemType.swift" "$src/Models/CanvasItem.swift" "$src/Models/YearDocument.swift" "$src/Models/VisionBoard.swift" "$src/Models/VisionBoardItem.swift")
mkdir "$build/legacy"
for model in CanvasItemType CanvasItem YearDocument VisionBoard VisionBoardItem; do
  git show "c691d48:Petals/Petals/Models/$model.swift" > "$build/legacy/$model.swift"
done
xcrun swiftc "${flags[@]}" -module-name PetalsMigrationFixture "$build"/legacy/*.swift "$repo/Tests/LegacyStoreSeed.swift" -o "$build/legacy-seed"
"$build/legacy-seed" "$build/legacy.store"
xcrun swiftc "${flags[@]}" -module-name PetalsMigrationFixture "${models[@]}" \
  "$src/Models/PlanningBoard.swift" "$src/Models/CalendarNote.swift" \
  "$src/Models/PlanningBoardMigration.swift" "$src/Models/PlanningBoardOperations.swift" \
  "$src/Models/PlanningBoardProjection.swift" "$src/Models/CanvasItemSnapshot.swift" \
  "$src/Models/ImageSyncMigration.swift" \
  "$src/Models/CalendarSet.swift" \
  "$src/Helpers/ImageManager.swift" "$repo/Tests/PlanningPersistenceChecks.swift" -o "$build/persistence"
"$build/persistence" "$build/legacy.store"
render=("$src/Settings/AppSettings.swift" "$src/Views/EventBarLayer.swift" "$src/Views/CalendarGridView.swift" "$src/Helpers/CalendarLayout.swift" "$src/EventKit/EventLayoutEngine.swift" "$src/Theme/Theme.swift")
xcrun swiftc "${flags[@]}" "${render[@]}" "$repo/Tests/SearchThemeChecks.swift" -o "$build/search"
"$build/search"
xcrun swiftc "${flags[@]}" "${render[@]}" \
  "$src/Views/CalendarExportView.swift" "$src/Helpers/CalendarExporter.swift" \
  "$src/Views/CanvasItemView.swift" "$src/Views/ItemImageView.swift" "$src/Helpers/ImageManager.swift" \
  "$src/Models/CanvasItem.swift" "$src/Models/CanvasItemType.swift" "$src/Models/YearDocument.swift" \
  "$src/Views/MoodBoardBackground.swift" "$repo/Tests/CalendarExportChecks.swift" -o "$build/export"
"$build/export"
echo 'PASS: local planning checks; export artifacts: /tmp/Petals-export-checks'
echo 'CloudKit and interactive UI checks are separate; this script does not access iCloud.'
