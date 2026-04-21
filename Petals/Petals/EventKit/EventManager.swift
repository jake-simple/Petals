import EventKit

@Observable
@MainActor
final class EventManager {
    private let store = EKEventStore()
    private(set) var calendars: [EKCalendar] = []
    private(set) var events: [EKEvent] = []
    private(set) var isAuthorized = false
    private var loadedYear: Int?
    private var hasRequestedAccess = false
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
            // First launch: select all
            selectedCalendarIDs = Set(calendars.map(\.calendarIdentifier))
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

    private func setupNotifications() {
        storeObserverToken = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadedYear = nil
                self?.loadCalendars()
            }
        }
    }
}
