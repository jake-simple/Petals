import Foundation
import SwiftData
import EventKit

/// User content is synced; the currently open board and viewport remain device-local.
@Model
final class PlanningBoard {
    var id: String = UUID().uuidString
    var recordID: String = UUID().uuidString
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    var name: String = ""
    var theme: String = "minimal-light"
    var createdAt: Date = Date()
    var calendarSelectionData: Data?
    /// A tombstone avoids resurrecting deleted boards when a second Mac migrates.
    var deletedAt: Date?

    init(id: String = UUID().uuidString, name: String, theme: String = "minimal-light") {
        self.id = id
        self.name = name
        self.theme = theme
    }

    var calendarSelection: [PlanningCalendarReference] {
        get { calendarSelectionData.flatMap { try? JSONDecoder().decode([PlanningCalendarReference].self, from: $0) } ?? [] }
        set {
            calendarSelectionData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
}

/// EventKit identifiers may differ across Macs. Preserve source metadata and only
/// use the fallback when there is exactly one match; never select an ambiguous calendar.
struct PlanningCalendarReference: Codable, Equatable {
    var identifier: String
    var title: String
    var sourceTitle: String
    var sourceType: Int
    var calendarType: Int

    init(calendar: EKCalendar) {
        identifier = calendar.calendarIdentifier
        title = calendar.title
        sourceTitle = calendar.source?.title ?? ""
        sourceType = calendar.source.map { Int($0.sourceType.rawValue) } ?? -1
        calendarType = Int(calendar.type.rawValue)
    }

    init(legacyIdentifier: String) {
        identifier = legacyIdentifier
        title = ""
        sourceTitle = ""
        sourceType = -1
        calendarType = -1
    }

    func resolve(in calendars: [EKCalendar]) -> EKCalendar? {
        if let exact = calendars.first(where: { $0.calendarIdentifier == identifier }) { return exact }
        guard !title.isEmpty else { return nil }
        let matches = calendars.filter {
            $0.title == title && ($0.source?.title ?? "") == sourceTitle &&
            $0.source.map { Int($0.sourceType.rawValue) } == sourceType && Int($0.type.rawValue) == calendarType
        }
        return matches.count == 1 ? matches.first : nil
    }
}
