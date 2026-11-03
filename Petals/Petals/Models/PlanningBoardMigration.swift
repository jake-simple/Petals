import Foundation
import SwiftData
import EventKit

@MainActor
enum PlanningBoardMigration {
    static let defaultBoardID = "legacy-set-default"

    /// Stable IDs let devices associate their legacy content with the same board.
    /// Keep the original preferences as a recovery source; commit the marker only
    /// after SwiftData saves successfully.
    static func migrate(in context: ModelContext, defaults: UserDefaults = .standard,
                        calendars: [EKCalendar] = []) throws -> String {
        let marker = "planningBoardMigrationV1"
        if defaults.bool(forKey: marker) {
            return defaults.string(forKey: "activePlanningBoardID") ?? defaultBoardID
        }
        let existing = try context.fetch(FetchDescriptor<PlanningBoard>())
        let legacySets = defaults.data(forKey: "calendarSets")
            .flatMap { try? JSONDecoder().decode([CalendarSet].self, from: $0) }
        let sets = legacySets?.isEmpty == false ? legacySets! : [
            CalendarSet(id: CalendarSet.defaultID, name: String(localized: "Default"),
                        calendarIDs: defaults.stringArray(forKey: "selectedCalendarIDs") ?? [])
        ]
        let activeSetID = defaults.string(forKey: "activeCalendarSetID") ?? CalendarSet.defaultID
        let activeID = "legacy-set-" + (sets.contains { $0.id == activeSetID } ? activeSetID : sets[0].id)
        let documents = try context.fetch(FetchDescriptor<YearDocument>())
        var boards = existing
        for set in sets {
            let id = "legacy-set-" + set.id
            guard !boards.contains(where: { $0.id == id }) else { continue }
            let board = PlanningBoard(id: id, name: set.name)
            board.calendarSelection = set.calendarIDs.map { identifier in
                calendars.first(where: { $0.calendarIdentifier == identifier })
                    .map(PlanningCalendarReference.init(calendar:)) ?? PlanningCalendarReference(legacyIdentifier: identifier)
            }
            if id == activeID {
                // Preserve each legacy document's theme too; board theme starts
                // from the most recently edited document.
                board.theme = documents.sorted { $0.modifiedAt > $1.modifiedAt }.first?.theme ?? "minimal-light"
            }
            context.insert(board)
            boards.append(board)
        }
        for document in documents where document.boardID.isEmpty {
            document.boardID = activeID
        }
        try context.save()
        defaults.set(activeID, forKey: "activePlanningBoardID")
        defaults.set(true, forKey: marker)
        return activeID
    }
}
