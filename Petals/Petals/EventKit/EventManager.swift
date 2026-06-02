import EventKit
import CoreGraphics

@Observable
@MainActor
final class EventManager {
    private let store = EKEventStore()
    private(set) var calendars: [EKCalendar] = []
    private(set) var events: [EKEvent] = []
    private(set) var isAuthorized = false
    private var loadedYear: Int?
    private var hasRequestedAccess = false
    @ObservationIgnored
    nonisolated(unsafe) private var storeObserverToken: Any?

    var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
            if oldValue != selectedCalendarIDs { loadedYear = nil }
        }
    }

    func requestAccess() async {
        if hasRequestedAccess { return }
        hasRequestedAccess = true
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        isAuthorized = granted
        if granted {
            loadCalendars()
            setupNotifications()
        }
    }

    deinit {
        if let token = storeObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func loadCalendars() {
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        restoreSelectedIDs()
    }

    private func restoreSelectedIDs() {
        if let stored = UserDefaults.standard.array(forKey: "selectedCalendarIDs") as? [String] {
            selectedCalendarIDs = Set(stored)
        } else {
            // First launch: none selected
            selectedCalendarIDs = []
        }
    }

    func fetchEvents(for year: Int) async {
        if loadedYear == year { return }
        let cal = Calendar.current
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return }

        let selectedCals = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !selectedCals.isEmpty else {
            events = []
            loadedYear = year
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selectedCals)
        let fetched = await Task.detached { [store] in
            store.events(matching: predicate)
        }.value
        events = fetched
        loadedYear = year
    }

    func createEvent(title: String, startDate: Date, endDate: Date, calendar: EKCalendar,
                     notes: String? = nil, isAllDay: Bool = true) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        event.notes = notes
        event.isAllDay = isAllDay
        try store.save(event, span: .thisEvent)
    }

    func updateEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.save(event, span: span)
    }

    func deleteEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span)
    }

    var defaultCalendar: EKCalendar? {
        store.defaultCalendarForNewEvents
    }

    // MARK: - Demo data (screenshot mode)

    /// Populates the manager with synthetic demo calendars + events for
    /// marketing screenshots. Requires no EventKit permission because the
    /// events are created in memory and never saved to the store.
    func loadDemoEvents(for year: Int) {
        let demoCalendars = Self.makeDemoCalendars(store: store)
        calendars = demoCalendars
        events = Self.makeDemoEvents(year: year, calendars: demoCalendars, store: store)
        isAuthorized = true
        loadedYear = year
    }

    private static func makeDemoCalendars(store: EKEventStore) -> [EKCalendar] {
        let specs: [(String, (Double, Double, Double))] = [
            ("Work",     (0.99, 0.27, 0.21)),
            ("Personal", (0.00, 0.48, 1.00)),
            ("Travel",   (0.20, 0.78, 0.35)),
            ("Health",   (1.00, 0.58, 0.00)),
            ("Family",   (0.69, 0.32, 0.87)),
        ]
        return specs.map { title, rgb in
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.cgColor = CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            return calendar
        }
    }

    private static func makeDemoEvents(year: Int, calendars: [EKCalendar], store: EKEventStore) -> [EKEvent] {
        let titles = [
            "Product launch", "Team offsite", "Sprint planning", "Design review",
            "Conference", "Vacation", "Q3 roadmap", "Release 2.0", "User research",
            "Marketing push", "Beta program", "Onboarding week", "All-hands",
            "Hiring round", "Workshop", "Retrospective", "Strategy sync",
            "Field trip", "Launch prep", "Customer visit", "Code freeze",
            "Annual review", "Spring break", "Demo day",
        ]
        let cal = Calendar.current
        var rng = SeededGenerator(seed: 0x5045_5441_4C53) // "PETALS"
        var result: [EKEvent] = []

        for month in 1...12 {
            guard let monthDate = cal.date(from: DateComponents(year: year, month: month)),
                  let range = cal.range(of: .day, in: .month, for: monthDate) else { continue }
            let daysInMonth = range.count
            let count = Int.random(in: 4...6, using: &rng)
            for _ in 0..<count {
                let span = Int.random(in: 2...9, using: &rng)
                let startDay = Int.random(in: 1...max(1, daysInMonth - span), using: &rng)
                guard let start = cal.date(from: DateComponents(year: year, month: month, day: startDay)),
                      let end = cal.date(from: DateComponents(year: year, month: month, day: min(daysInMonth, startDay + span - 1)))
                else { continue }
                let event = EKEvent(eventStore: store)
                event.title = titles.randomElement(using: &rng) ?? "Event"
                event.startDate = start
                event.endDate = end
                event.isAllDay = true
                event.calendar = calendars.randomElement(using: &rng)
                result.append(event)
            }
        }
        return result
    }

    private func setupNotifications() {
        storeObserverToken = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadedYear = nil
                self?.loadCalendars()
            }
        }
    }
}

/// Deterministic RNG so demo screenshots are byte-identical between runs.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
