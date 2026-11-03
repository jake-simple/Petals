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
    private var fetchGeneration = 0
    private(set) var storeRevision = 0

    private func invalidateEvents() {
        loadedYear = nil
        fetchGeneration += 1
    }
    private var hasRequestedAccess = false
    @ObservationIgnored
    nonisolated(unsafe) private var storeObserverToken: Any?

    /// The calendars whose events are currently rendered. This is always a
    /// mirror of the active set's membership — edit it through the calendar-set
    /// methods below, not by assigning directly.
    var selectedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
            if oldValue != selectedCalendarIDs { invalidateEvents() }
        }
    }

    // MARK: - Calendar Sets

    private static let setsKey = "calendarSets"
    private static let activeSetKey = "activeCalendarSetID"

    private(set) var calendarSets: [CalendarSet] = []
    private(set) var activeCalendarSetID: String = CalendarSet.defaultID

    var activeSet: CalendarSet? {
        calendarSets.first { $0.id == activeCalendarSetID }
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
        calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        restoreCalendarSets()
    }

    private func restoreCalendarSets() {
        // Load saved sets; require the undeletable Default set to be present,
        // otherwise migrate the legacy selection into a fresh Default set.
        if let data = UserDefaults.standard.data(forKey: Self.setsKey),
           let sets = try? JSONDecoder().decode([CalendarSet].self, from: data),
           sets.contains(where: { $0.isDefault }) {
            calendarSets = sets
        } else {
            // First launch of this version: seed Default from the legacy
            // `selectedCalendarIDs` so no one loses their selection.
            let legacy = UserDefaults.standard.array(forKey: "selectedCalendarIDs") as? [String] ?? []
            calendarSets = [CalendarSet(id: CalendarSet.defaultID,
                                        name: String(localized: "Default"),
                                        calendarIDs: legacy.sorted())]
            persistSets()
        }

        // Restore the active set, falling back to Default if it's gone.
        let storedActive = UserDefaults.standard.string(forKey: Self.activeSetKey)
        if let storedActive, calendarSets.contains(where: { $0.id == storedActive }) {
            activeCalendarSetID = storedActive
        } else {
            activeCalendarSetID = CalendarSet.defaultID
            UserDefaults.standard.set(activeCalendarSetID, forKey: Self.activeSetKey)
        }

        applyActiveSetToSelection()
    }

    private func applyActiveSetToSelection() {
        selectedCalendarIDs = Set(activeSet?.calendarIDs ?? [])
    }

    // MARK: - Calendar Set editing

    /// Switch the single active set; the rendered selection follows.
    func selectSet(id: String) {
        guard calendarSets.contains(where: { $0.id == id }) else { return }
        activeCalendarSetID = id
        UserDefaults.standard.set(id, forKey: Self.activeSetKey)
        applyActiveSetToSelection()
    }

    /// Toggle one calendar's membership in the currently active set (live edit).
    func setCalendar(_ calendarID: String, enabled: Bool) {
        updateActiveSet { ids in
            if enabled { ids.insert(calendarID) } else { ids.remove(calendarID) }
        }
    }

    /// Replace the active set's membership wholesale (Select All / None).
    func setActiveSetCalendars(_ ids: Set<String>) {
        updateActiveSet { $0 = ids }
    }

    private func updateActiveSet(_ mutate: (inout Set<String>) -> Void) {
        guard let idx = calendarSets.firstIndex(where: { $0.id == activeCalendarSetID }) else { return }
        var ids = Set(calendarSets[idx].calendarIDs)
        mutate(&ids)
        calendarSets[idx].calendarIDs = ids.sorted()
        persistSets()
        selectedCalendarIDs = ids
    }

    /// Snapshot a set of calendars into a new named set.
    /// - Parameter activate: switch to it after creating (default true).
    @discardableResult
    func createSet(name: String, calendarIDs: Set<String>, activate: Bool = true) -> String {
        let id = UUID().uuidString
        calendarSets.append(CalendarSet(id: id, name: name, calendarIDs: calendarIDs.sorted()))
        persistSets()
        if activate { selectSet(id: id) }
        return id
    }

    func renameSet(id: String, to name: String) {
        guard let idx = calendarSets.firstIndex(where: { $0.id == id }) else { return }
        calendarSets[idx].name = name
        persistSets()
    }

    func deleteSet(id: String) {
        guard id != CalendarSet.defaultID else { return }   // Default is undeletable
        calendarSets.removeAll { $0.id == id }
        persistSets()
        if activeCalendarSetID == id {
            selectSet(id: CalendarSet.defaultID)             // fall back to Default
        }
    }

    func moveSets(fromOffsets: IndexSet, toOffset: Int) {
        // Matches SwiftUI's Collection.move(fromOffsets:toOffset:) without
        // importing SwiftUI into this logic layer.
        let moving = fromOffsets.map { calendarSets[$0] }
        var result = calendarSets
        for index in fromOffsets.sorted(by: >) {
            result.remove(at: index)
        }
        let insertionIndex = toOffset - fromOffsets.filter { $0 < toOffset }.count
        result.insert(contentsOf: moving, at: insertionIndex)
        calendarSets = result
        persistSets()
    }

    private func persistSets() {
        if let data = try? JSONEncoder().encode(calendarSets) {
            UserDefaults.standard.set(data, forKey: Self.setsKey)
        }
    }

    func fetchEvents(for year: Int) async {
        guard !Task.isCancelled else { return }
        fetchGeneration += 1
        let generation = fetchGeneration
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
        guard !Task.isCancelled, generation == fetchGeneration else { return }
        events = fetched
        loadedYear = year
    }

    func createEvent(title: String, startDate: Date, endDate: Date, calendar: EKCalendar,
                     notes: String? = nil, isAllDay: Bool = true,
                     location: String? = nil, url: URL? = nil) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        event.notes = notes
        event.isAllDay = isAllDay
        event.location = location
        event.url = url
        try store.save(event, span: .thisEvent)
        invalidateEvents()
    }

    func updateEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.save(event, span: span)
        invalidateEvents()
    }

    func deleteEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span)
        invalidateEvents()
    }

    var defaultCalendar: EKCalendar? {
        store.defaultCalendarForNewEvents
    }

    // MARK: - On This Day

    func fetchEventsForDate(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        guard let start = cal.startOfDay(for: date) as Date?,
              let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let cals = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: predicate)
    }

    func fetchOnThisDay(
        for date: Date,
        yearsBack: Int = 25,
        onBatchComplete: @MainActor @Sendable ([(year: Int, events: [EKEvent])]) -> Void
    ) async {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let currentYear = cal.component(.year, from: date)

        let batchSize = 4
        for batchStart in stride(from: 1, through: yearsBack, by: batchSize) {
            guard !Task.isCancelled else { return }
            let batchEnd = min(batchStart + batchSize - 1, yearsBack)

            var batchResults: [(year: Int, events: [EKEvent])] = []
            for offset in batchStart...batchEnd {
                let targetYear = currentYear - offset
                var components = DateComponents()
                components.year = targetYear
                components.month = month
                components.day = day
                guard let targetDate = cal.date(from: components),
                      cal.component(.month, from: targetDate) == month,
                      cal.component(.day, from: targetDate) == day,
                      let start = cal.date(bySettingHour: 0, minute: 0, second: 0, of: targetDate),
                      let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
                let cals = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
                guard !cals.isEmpty else { continue }
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
                let fetched = store.events(matching: predicate)
                if !fetched.isEmpty {
                    batchResults.append((year: targetYear, events: fetched))
                }
            }

            if !batchResults.isEmpty {
                onBatchComplete(batchResults.sorted { $0.year > $1.year })
            }
        }
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
        let titles = ScreenshotConfig.isKorean
            ? ["업무", "개인", "여행", "건강", "가족"]
            : ["Work", "Personal", "Travel", "Health", "Family"]
        let colors: [(Double, Double, Double)] = [
            (0.99, 0.27, 0.21), (0.00, 0.48, 1.00), (0.20, 0.78, 0.35),
            (1.00, 0.58, 0.00), (0.69, 0.32, 0.87),
        ]
        let specs = Array(zip(titles, colors))
        return specs.map { title, rgb in
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.cgColor = CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            return calendar
        }
    }

    private static func makeDemoEvents(year: Int, calendars: [EKCalendar], store: EKEventStore) -> [EKEvent] {
        let titles = ScreenshotConfig.isKorean
            ? [
                "제품 출시", "팀 워크숍", "스프린트 계획", "디자인 리뷰",
                "컨퍼런스", "휴가", "3분기 로드맵", "2.0 출시", "사용자 리서치",
                "마케팅 캠페인", "베타 프로그램", "온보딩 주간", "전사 회의",
                "채용 라운드", "워크숍", "회고", "전략 미팅",
                "현장 견학", "출시 준비", "고객 미팅", "코드 프리즈",
                "연간 리뷰", "봄 휴가", "데모 데이",
            ]
            : [
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
                guard let self else { return }
                self.invalidateEvents()
                self.loadCalendars()
                self.storeRevision += 1
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
