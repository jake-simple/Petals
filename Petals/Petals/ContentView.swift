import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var currentYear = Calendar.current.component(.year, from: Date())
    @State private var eventManager = EventManager()
    @State private var currentDocument: YearDocument?

    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault
    @AppStorage("obfuscateEventText") private var obfuscateText = false
    @AppStorage("hideSingleDayEvents") private var hideSingleDayEvents = false
    @AppStorage("eventFontSize") private var eventFontSize = AppSettings.eventFontSizeDefault

    // Cached layout (recomputed only on data change)
    @State private var segments: [EventSegment] = []
    @State private var overflows: [Int: [Int: Int]] = [:]

    // Event state
    @State private var selectedEvent: EKEvent?
    @State private var showEventDetail = false
    @State private var showEventEditor = false
    @State private var showCalendarFilter = false
    @State private var showFontSizePicker = false
    @State private var editorStartDate: Date?
    @State private var editorEndDate: Date?

    // Paging state
    @State private var monthsPerPage = 12  // 12, 6, 3
    @State private var pageIndex = 0

    // Canvas state
    @State private var isCanvasEditMode = false
    @State private var selectedCanvasItemID: PersistentIdentifier?
    @State private var showImagePicker = false
    @State private var showInspector = false
    @State private var showThemePicker = false
    @State private var scrollMonitor: Any?
    @State private var accumulatedScrollX: CGFloat = 0

    private var theme: Theme {
        let themeID = currentDocument?.theme ?? "minimal-light"
        return ThemeManager.shared.theme(for: themeID)
    }

    private var selectedCanvasItem: CanvasItem? {
        guard let id = selectedCanvasItemID else { return nil }
        return currentDocument?.canvasItems?.first { $0.persistentModelID == id }
    }

    private var startMonth: Int { pageIndex * monthsPerPage + 1 }
    private var maxPageIndex: Int { (12 / monthsPerPage) - 1 }

    private var daysPerRow: Int {
        switch monthsPerPage {
        case 6: return 16
        case 3: return 8
        default: return 31
        }
    }

    /// Segments filtered to visible months and split at subrow boundaries.
    private var visibleSegments: [EventSegment] {
        let endMonth = startMonth + monthsPerPage - 1
        let dpr = daysPerRow
        var result: [EventSegment] = []
        for seg in segments {
            guard seg.month >= startMonth, seg.month <= endMonth else { continue }
            // Split segment at subrow boundaries
            var day = seg.startDay
            while day <= seg.endDay {
                let rowEnd = ((day - 1) / dpr + 1) * dpr
                let segEnd = min(seg.endDay, rowEnd)
                result.append(EventSegment(
                    id: "\(seg.id)_\(day)",
                    event: seg.event,
                    month: seg.month,
                    startDay: day,
                    endDay: segEnd,
                    lane: seg.lane
                ))
                day = segEnd + 1
            }
        }
        return result
    }

    /// Overflows filtered to visible months.
    private var visibleOverflows: [Int: [Int: Int]] {
        let endMonth = startMonth + monthsPerPage - 1
        return overflows.filter { $0.key >= startMonth && $0.key <= endMonth }
    }

    var body: some View {
        ZStack {
            Color(hex: theme.backgroundColor)
                .ignoresSafeArea()

            ZStack {
                // Z1: Grid + today line
                CalendarGridView(
                    year: currentYear, theme: theme, showTodayLine: showTodayLine,
                    eventFontSize: CGFloat(eventFontSize),
                    startMonth: startMonth, monthsShown: monthsPerPage
                )
                .allowsHitTesting(false)

                // Z2: Event bars (hidden in canvas edit mode)
                if !isCanvasEditMode {
                    EventBarLayer(
                        segments: visibleSegments,
                        overflows: visibleOverflows,
                        maxEventRows: maxEventRows,
                        obfuscateText: obfuscateText,
                        eventFontSize: CGFloat(eventFontSize),
                        startMonth: startMonth,
                        monthsShown: monthsPerPage,
                        onEventTap: { event in
                            selectedEvent = event
                            showEventDetail = true
                        },
                        onEmptyTap: { month, day in
                            openEditor(month: month, startDay: day, endDay: day)
                        },
                        onDragCreate: { month, startDay, _, endDay in
                            openEditor(month: month, startDay: startDay, endDay: endDay)
                        }
                    )
                }

                // Z3: Canvas items
                if isCanvasEditMode {
                    CanvasLayer(
                        yearDocument: currentDocument,
                        selectedItemID: $selectedCanvasItemID
                    )
                } else {
                    canvasDisplayLayer
                }
            }
            .gesture(
                MagnifyGesture()
                    .onEnded { value in
                        if value.magnification > 1.3 {
                            zoomIn()
                        } else if value.magnification < 0.7 {
                            zoomOut()
                        }
                    }
            )
        }
        .toolbar { toolbarContent }
        .popover(isPresented: $showEventDetail, attachmentAnchor: .point(.center)) {
            if let event = selectedEvent {
                EventDetailPopover(
                    event: event,
                    onEdit: {
                        showEventDetail = false
                        selectedEvent = event
                        editorStartDate = nil
                        editorEndDate = nil
                        showEventEditor = true
                    },
                    onDelete: { span in
                        try? eventManager.deleteEvent(event, span: span)
                        showEventDetail = false
                        selectedEvent = nil
                        reloadEvents()
                    }
                )
            }
        }
        .popover(isPresented: $showInspector) {
            if let item = selectedCanvasItem {
                InspectorPanel(item: item) {
                    deleteSelectedCanvasItem()
                }
            }
        }
        .sheet(isPresented: $showEventEditor) {
            EventEditorSheet(
                eventManager: eventManager,
                existingEvent: selectedEvent,
                initialStartDate: editorStartDate,
                initialEndDate: editorEndDate,
                onSave: { reloadEvents() }
            )
        }
        .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                importImage(from: url)
            }
        }
        .task {
            await eventManager.requestAccess()
            reloadEvents()
        }
        .onAppear {
            loadDocument(for: currentYear)
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if event.phase == .began {
                    accumulatedScrollX = 0
                }
                accumulatedScrollX += event.scrollingDeltaX
                if event.phase == .ended {
                    if accumulatedScrollX < -50 {
                        if monthsPerPage < 12 {
                            pageIndex = min(maxPageIndex, pageIndex + 1)
                        } else {
                            currentYear += 1
                        }
                    } else if accumulatedScrollX > 50 {
                        if monthsPerPage < 12 {
                            pageIndex = max(0, pageIndex - 1)
                        } else {
                            currentYear -= 1
                        }
                    }
                    accumulatedScrollX = 0
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
        .onChange(of: currentYear) { _, newYear in
            loadDocument(for: newYear)
            reloadEvents()
            selectedCanvasItemID = nil
        }
        .onChange(of: eventManager.selectedCalendarIDs) {
            reloadEvents()
        }
        .onChange(of: hideSingleDayEvents) {
            recomputeLayout()
        }
        .onChange(of: maxEventRows) {
            recomputeLayout()
        }
    }

    // MARK: - Display-only canvas (non-edit mode)

    @ViewBuilder
    private var canvasDisplayLayer: some View {
        GeometryReader { proxy in
            ForEach((currentDocument?.canvasItems ?? []).sorted { $0.zIndex < $1.zIndex }) { item in
                CanvasItemView(item: item)
                    .frame(
                        width: item.relativeWidth * proxy.size.width,
                        height: item.relativeHeight * proxy.size.height
                    )
                    .rotationEffect(.degrees(item.rotation))
                    .opacity(item.opacity)
                    .position(
                        x: item.relativeX * proxy.size.width + item.relativeWidth * proxy.size.width / 2,
                        y: item.relativeY * proxy.size.height + item.relativeHeight * proxy.size.height / 2
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Button(action: { currentYear -= 1 }) { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Text(String(currentYear))
                    .font(.title2.bold()).monospacedDigit().frame(minWidth: 60)
                Button(action: { currentYear += 1 }) { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Today") { currentYear = Calendar.current.component(.year, from: Date()) }
                    .keyboardShortcut("t", modifiers: .command)

                Divider().frame(height: 16)

                // Zoom level (months per page)
                Button(action: { zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("=", modifiers: [.command, .option])
                .disabled(monthsPerPage <= 3)

                Text("\(monthsPerPage)M")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 30)

                Button(action: { zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: [.command, .option])
                .disabled(monthsPerPage >= 12)

                if monthsPerPage < 12 {
                    // Page navigation
                    Button(action: { pageIndex = max(0, pageIndex - 1) }) {
                        Image(systemName: "chevron.left.2")
                    }
                    .disabled(pageIndex <= 0)

                    Text("\(startMonth)–\(startMonth + monthsPerPage - 1)")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 36)

                    Button(action: { pageIndex = min(maxPageIndex, pageIndex + 1) }) {
                        Image(systemName: "chevron.right.2")
                    }
                    .disabled(pageIndex >= maxPageIndex)

                    Button("All") {
                        monthsPerPage = 12
                        pageIndex = 0
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                // Event tools
                Button(action: {
                    editorStartDate = nil; editorEndDate = nil; selectedEvent = nil
                    showEventEditor = true
                }) { Label("New Event", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)

                Button(action: { showCalendarFilter.toggle() }) {
                    Label("Calendars", systemImage: "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showCalendarFilter) {
                    CalendarFilterView(eventManager: eventManager)
                }

                Button(action: { showFontSizePicker.toggle() }) {
                    Label("Font Size", systemImage: "textformat.size")
                }
                .popover(isPresented: $showFontSizePicker) {
                    VStack(spacing: 8) {
                        Text("Event Font Size: \(Int(eventFontSize))pt")
                            .font(.headline)
                        Slider(value: $eventFontSize, in: 6...20, step: 1)
                            .frame(width: 160)
                    }
                    .padding()
                }

                Divider()

                // Theme picker
                Button(action: { showThemePicker.toggle() }) {
                    Label("Theme", systemImage: "paintpalette")
                }
                .popover(isPresented: $showThemePicker) {
                    ThemePickerView(
                        themes: ThemeManager.shared.themes,
                        selectedThemeID: Binding(
                            get: { currentDocument?.theme ?? "minimal-light" },
                            set: { currentDocument?.theme = $0 }
                        )
                    )
                }

                Divider()

                // Canvas edit mode toggle
                Toggle(isOn: $isCanvasEditMode) {
                    Label("Canvas", systemImage: "paintbrush")
                }
                .toggleStyle(.button)

                if isCanvasEditMode {
                    canvasToolButtons
                }
            }
        }
    }

    @ViewBuilder
    private var canvasToolButtons: some View {
        Button(action: { showImagePicker = true }) {
            Label("Image", systemImage: "photo")
        }
        Button(action: {
            if let doc = currentDocument { addCanvasItem(.newText(zIndex: doc.nextZIndex)) }
        }) {
            Label("Text", systemImage: "textformat")
        }
        Menu {
            Button("Rectangle") { if let doc = currentDocument { addCanvasItem(.newShape("rectangle", zIndex: doc.nextZIndex)) } }
            Button("Circle") { if let doc = currentDocument { addCanvasItem(.newShape("circle", zIndex: doc.nextZIndex)) } }
            Button("Line") { if let doc = currentDocument { addCanvasItem(.newShape("line", zIndex: doc.nextZIndex)) } }
        } label: {
            Label("Shape", systemImage: "square.on.circle")
        }
        Menu {
            Button("Star") { if let doc = currentDocument { addCanvasItem(.newSticker("star.fill", zIndex: doc.nextZIndex)) } }
            Button("Heart") { if let doc = currentDocument { addCanvasItem(.newSticker("heart.fill", zIndex: doc.nextZIndex)) } }
            Button("Bell") { if let doc = currentDocument { addCanvasItem(.newSticker("bell.fill", zIndex: doc.nextZIndex)) } }
            Button("Flag") { if let doc = currentDocument { addCanvasItem(.newSticker("flag.fill", zIndex: doc.nextZIndex)) } }
            Button("Pin") { if let doc = currentDocument { addCanvasItem(.newSticker("pin.fill", zIndex: doc.nextZIndex)) } }
        } label: {
            Label("Sticker", systemImage: "face.smiling")
        }

        if selectedCanvasItemID != nil {
            Button(action: { showInspector = true }) {
                Label("Inspector", systemImage: "slider.horizontal.3")
            }
            Button(action: { bringSelectedToFront() }) {
                Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
            }
            .keyboardShortcut("]", modifiers: .command)

            Button(action: { sendSelectedToBack() }) {
                Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
            }
            .keyboardShortcut("[", modifiers: .command)
        }
    }

    // MARK: - Actions

    private func zoomIn() {
        let next: Int
        switch monthsPerPage {
        case 12: next = 6
        case 6: next = 3
        default: return
        }
        monthsPerPage = next
        pageIndex = 0
    }

    private func zoomOut() {
        let next: Int
        switch monthsPerPage {
        case 3: next = 6
        case 6: next = 12
        default: return
        }
        monthsPerPage = next
        pageIndex = 0
    }

    private func reloadEvents() {
        eventManager.fetchEvents(for: currentYear)
        recomputeLayout()
    }

    private func recomputeLayout() {
        let events: [EKEvent]
        if hideSingleDayEvents {
            let cal = Calendar.current
            events = eventManager.events.filter { event in
                guard let start = event.startDate, let end = event.endDate else { return true }
                let adjustedEnd = event.isAllDay
                    ? (cal.date(byAdding: .day, value: -1, to: end) ?? end)
                    : end
                return !cal.isDate(start, inSameDayAs: adjustedEnd)
            }
        } else {
            events = eventManager.events
        }
        segments = EventLayoutEngine.layout(events: events, year: currentYear, maxLanes: maxEventRows)
        overflows = EventLayoutEngine.overflowCounts(events: events, year: currentYear, maxLanes: maxEventRows)
    }

    private func openEditor(month: Int, startDay: Int, endDay: Int) {
        let cal = Calendar.current
        editorStartDate = cal.date(from: DateComponents(year: currentYear, month: month, day: startDay))
        editorEndDate = cal.date(from: DateComponents(year: currentYear, month: month, day: endDay))
        selectedEvent = nil
        showEventEditor = true
    }

    private func loadDocument(for year: Int) {
        let descriptor = FetchDescriptor<YearDocument>(predicate: #Predicate { $0.year == year })
        if let doc = (try? modelContext.fetch(descriptor))?.first {
            currentDocument = doc
        } else {
            let doc = YearDocument(year: year)
            modelContext.insert(doc)
            currentDocument = doc
        }
    }

    private func importImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let result = ImageManager.importImage(from: url),
              let doc = currentDocument else { return }
        let item = CanvasItem.newImage(fileName: result.fileName, thumbnail: result.thumbnail, zIndex: doc.nextZIndex)
        doc.appendItem(item)
        selectedCanvasItemID = item.persistentModelID
    }

    private func addCanvasItem(_ item: CanvasItem) {
        guard let doc = currentDocument else { return }
        doc.appendItem(item)
        selectedCanvasItemID = item.persistentModelID
    }

    private func bringSelectedToFront() {
        guard let item = selectedCanvasItem, let doc = currentDocument else { return }
        item.zIndex = doc.nextZIndex
    }

    private func sendSelectedToBack() {
        guard let item = selectedCanvasItem, let doc = currentDocument else { return }
        item.zIndex = doc.minZIndex
    }

    private func deleteSelectedCanvasItem() {
        guard let id = selectedCanvasItemID,
              let item = currentDocument?.canvasItems?.first(where: { $0.persistentModelID == id }) else { return }
        currentDocument?.removeItem { $0.persistentModelID == id }
        modelContext.delete(item)
        selectedCanvasItemID = nil
        showInspector = false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [YearDocument.self, CanvasItem.self], inMemory: true)
}
