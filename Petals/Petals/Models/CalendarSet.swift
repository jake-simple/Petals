import Foundation

/// A named combination of calendars the user can switch between (like
/// Fantastical's calendar sets). Only one set is active at a time; the
/// active set drives `EventManager.selectedCalendarIDs`.
///
/// Stored locally (UserDefaults, JSON). Membership is keyed by
/// `EKCalendar.calendarIdentifier` **only** — names and colors are always
/// resolved live from EventKit, so renaming a calendar never breaks a set,
/// and a temporarily-missing calendar is simply ignored (self-healing) rather
/// than pruned.
struct CalendarSet: Codable, Identifiable, Equatable {
    /// Reserved id for the built-in "Default" set, which can be renamed but
    /// never deleted.
    static let defaultID = "default"

    let id: String
    var name: String
    var calendarIDs: [String]

    var isDefault: Bool { id == Self.defaultID }
}
