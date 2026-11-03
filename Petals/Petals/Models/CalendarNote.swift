import Foundation
import SwiftData

@Model
final class CalendarNote {
    var id: String = UUID().uuidString
    var boardID: String = ""
    /// Civil date, not a timestamp: travelling must not move a note to another day.
    var year: Int = 2000
    var month: Int = 1
    var day: Int = 1
    var body: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(boardID: String, date: Date, body: String = "") {
        self.boardID = boardID
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 2000
        month = parts.month ?? 1
        day = parts.day ?? 1
        self.body = body
    }

    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? createdAt
    }

    var dateKey: Int { year * 10000 + month * 100 + day }
}
