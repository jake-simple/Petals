import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var currentYear = ScreenshotConfig.isActive
        ? ScreenshotConfig.year
        : Calendar.current.component(.year, from: Date())
    @State private var eventManager = EventManager()
    @State private var currentDocument: YearDocument?

    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("dimPastDates") private var dimPastDates = AppSettings.dimPastDatesDefault
    @AppStorage("collapseTopArea") private var collapseTopArea = false
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault
    @AppStorage("eventFontSize") private var eventFontSize = AppSettings.eventFontSizeDefault

    // Cached layout (recomputed only on data change)
    @State private var segments: [EventSegment] = []
    @State private var overflows: [Int: [Int: Int]] = [:]

    // Event state
    @State private var selectedEvent: EKEvent?
    @State private var showEventDetail = false
    @State private var eventPopoverAnchor: CGRect = .zero
    @State private var showDayDetail = false
    @State private var dayDetailDate = Date()
    @State private var editorContext: EventEditorContext?
    @State private var showCalendarFilter = false
    @State private var showFontSizePicker = false

    // Paging state
    @State private var monthsPerPage = ScreenshotConfig.zoom ?? 12  // 12, 3, 1
    @State private var pageIndex = 0

    // 화이트보드 모드
    @State private var showVisionBoard = ScreenshotConfig.startsInWhiteboard
    @State private var selectedVisionBoardID: PersistentIdentifier?

    // Canvas state
    @State private var isCanvasEditMode = false
    @State private var selectedCanvasItemIDs: Set<PersistentIdentifier> = []
    @State private var showImagePicker = false
    @State private var showInspector = false
    @State private var showThemePicker = false
    @State private var showStickerInput = false
    @State private var scrollMonitor: Any?
    @State private var accumulatedScrollX: CGFloat = 0
    @State private var fetchTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme {
        let themeID = ScreenshotConfig.theme ?? currentDocument?.theme ?? "minimal-light"
        return ThemeManager.shared.theme(for: themeID).resolved(for: colorScheme)
    }

    private var selectedCanvasItems: [CanvasItem] {
        guard !selectedCanvasItemIDs.isEmpty else { return [] }
        return (currentDocument?.canvasItems ?? []).filter { selectedCanvasItemIDs.contains($0.persistentModelID) }
    }

    private var startMonth: Int { pageIndex * monthsPerPage + 1 }
    private var maxPageIndex: Int { (12 / monthsPerPage) - 1 }

    /// Segments filtered to visible months and split at visual row boundaries.
    private var visibleSegments: [EventSegment] {
        let endMonth = startMonth + monthsPerPage - 1
        let layout = CalendarLayout(size: .zero, monthsShown: monthsPerPage, startMonth: startMonth, year: currentYear)
        var result: [EventSegment] = []
        for seg in segments {
            guard seg.month >= startMonth, seg.month <= endMonth else { continue }
            for run in layout.rowRuns(month: seg.month, startDay: seg.startDay, endDay: seg.endDay) {
                result.append(EventSegment(
                    id: "\(seg.id)_\(run.startDay)",
                    event: seg.event,
                    month: seg.month,
                    startDay: run.startDay,
                    endDay: run.endDay,
                    lane: seg.lane
                ))
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
        Group {
            if showVisionBoard {
                VisionBoardContainerView(selectedBoardID: $selectedVisionBoardID)
                    .toolbar { modeToggleToolbar }
            } else {
                calendarBody
            }
        }
        .navigationTitle(showVisionBoard ? "화이트보드" : "캘린더")
        .inspector(isPresented: $showCalendarFilter) {
            CalendarFilterView(eventManager: eventManager)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 400)
        }
        .overlay(alignment: .bottom) {
            if clipboardManager.showCopyToast {
                Text("복사됨")
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: clipboardManager.showCopyToast)
        .background(ToolbarConfigurator())
        .background(ScreenshotWindowSizer())
        .background {
            // 비전보드 모드에서는 Cmd+=/- 가 뷰포트 줌에 사용되므로 제외
            if !showVisionBoard {
                Group {
                    Button("Increase Font Size") {
                        eventFontSize = min(eventFontSize + 1, AppSettings.eventFontSizeRange.upperBound)
                    }
                    .keyboardShortcut("=", modifiers: .command)

                    Button("Decrease Font Size") {
                        eventFontSize = max(eventFontSize - 1, AppSettings.eventFontSizeRange.lowerBound)
                    }
                    .keyboardShortcut("-", modifiers: .command)
                }
                .hidden()
            }
        }
    }

    @ToolbarContentBuilder
    private var modeToggleToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showVisionBoard.toggle()
            } label: {
                Image(systemName: showVisionBoard ? "calendar" : "sparkles.rectangle.stack")
            }
            .help(showVisionBoard ? "캘린더 보기" : "화이트보드 보기")
        }
    }

    private var calendarBody: some View {
        GeometryReader { geo in
        ZStack {
            // Board background covers entire window
            MoodBoardBackground(gridLineColor: theme.gridLineColor)
                .ignoresSafeArea()

            // Calendar pinned onto the board with margin
            ZStack {
                Color(hex: theme.backgroundColor)

                ZStack {
                    // Z1: Grid + today line
                    CalendarGridView(
                        year: currentYear, theme: theme, showTodayLine: showTodayLine,
                        eventFontSize: CGFloat(eventFontSize),
                        startMonth: startMonth, monthsShown: monthsPerPage
                    )
                    .allowsHitTesting(false)

                    // Z2: Event bars
                    EventBarLayer(
                        year: currentYear,
                        segments: visibleSegments,
                        overflows: visibleOverflows,
                        maxEventRows: maxEventRows,
                        eventFontSize: CGFloat(eventFontSize),
                        theme: theme,
                        startMonth: startMonth,
                        monthsShown: monthsPerPage,
                        onEventTap: { event, rect in
                            selectedEvent = event
                            eventPopoverAnchor = rect
                            showEventDetail = true
                        },
                        onEmptyTap: { month, day in
                            let cal = Calendar.current
                            dayDetailDate = cal.date(from: DateComponents(year: currentYear, month: month, day: day)) ?? Date()
                            showDayDetail = true
                        },
                        onNewEvent: { month, day in
                            openEditor(startMonth: month, startDay: day, endMonth: month, endDay: day)
                        },
                        onDragCreate: { startMonth, startDay, endMonth, endDay in
                            openEditor(startMonth: startMonth, startDay: startDay, endMonth: endMonth, endDay: endDay)
                        },
                        onEventDelete: { event, span in
                            try? eventManager.deleteEvent(event, span: span)
                            reloadEvents()
                        }
                    )
                    .allowsHitTesting(!isCanvasEditMode)

                    // Z3: 지난 날짜 흐림 — 그리드·이벤트 바 위에 덮어 전부 흐리게
                    if dimPastDates {
                        PastDatesVeil(
                            year: currentYear, theme: theme,
                            startMonth: startMonth, monthsShown: monthsPerPage
                        )
                        .allowsHitTesting(false)
                    }
                }
                .popover(isPresented: $showEventDetail, attachmentAnchor: .rect(.rect(eventPopoverAnchor))) {
                    if let event = selectedEvent {
                        EventDetailPopover(
                            event: event,
                            onEdit: {
                                showEventDetail = false
                                editorContext = EventEditorContext(existingEvent: event)
                            }
                        )
                    }
                }
                .sheet(isPresented: $showDayDetail) {
                    DayEventsPopover(
                        date: dayDetailDate,
                        eventManager: eventManager,
                        onSaved: { reloadEvents() }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, collapseTopArea ? 16 : geo.size.height * 0.18)
            .padding(.bottom, 16)
            .allowsHitTesting(!isCanvasEditMode)
            // Canvas layer (편집/표시 모드 동일한 좌표계)
            Group {
                if isCanvasEditMode {
                    CanvasLayer(
                        yearDocument: currentDocument,
                        zoomLevel: monthsPerPage,
                        pageIndex: pageIndex,
                        selectedItemIDs: $selectedCanvasItemIDs,
                        showInspector: $showInspector
                    )
                } else {
                    canvasDisplayLayer
                }
            }
        }
        } // GeometryReader
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            modeToggleToolbar
            toolbarContent
        }
        .sheet(item: $editorContext) { ctx in
            EventEditorSheet(
                eventManager: eventManager,
                existingEvent: ctx.existingEvent,
                initialStartDate: ctx.startDate,
                initialEndDate: ctx.endDate,
                onSave: { reloadEvents() }
            )
        }
        .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                importImage(from: url)
            }
        }
        .task {
            if ScreenshotConfig.isActive {
                eventManager.loadDemoEvents(for: currentYear)
                recomputeLayout()
            } else {
                await eventManager.requestAccess()
                reloadEvents()
            }
        }
        .onAppear {
            loadDocument(for: currentYear)
            if let existing = scrollMonitor { NSEvent.removeMonitor(existing) }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard !showVisionBoard else { return event }
                if event.phase == .began {
                    accumulatedScrollX = 0
                }
                accumulatedScrollX += event.scrollingDeltaX
                if event.phase == .ended {
                    if accumulatedScrollX < -50 {
                        navigateForward()
                    } else if accumulatedScrollX > 50 {
                        navigateBack()
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
            selectedCanvasItemIDs.removeAll()
        }
        .onChange(of: monthsPerPage) { _, newValue in
            let now = Date()
            currentYear = Calendar.current.component(.year, from: now)
            let month = Calendar.current.component(.month, from: now)
            pageIndex = (month - 1) / newValue
            selectedCanvasItemIDs.removeAll()
        }
        .onChange(of: pageIndex) {
            selectedCanvasItemIDs.removeAll()
        }
        .onChange(of: isCanvasEditMode) { _, editing in
            if !editing {
                selectedCanvasItemIDs.removeAll()
                showInspector = false
            }
        }
        .onChange(of: eventManager.selectedCalendarIDs) {
            reloadEvents()
        }
        .onChange(of: maxEventRows) {
            recomputeLayout()
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            guard !isCanvasEditMode, !showVisionBoard else { return .ignored }
            navigateBack()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isCanvasEditMode, !showVisionBoard else { return .ignored }
            navigateForward()
            return .handled
        }
    }

    // MARK: - Display-only canvas (non-edit mode)

    @ViewBuilder
    private var canvasDisplayLayer: some View {
        GeometryReader { proxy in
            ForEach((currentDocument?.canvasItems(for: monthsPerPage, pageIndex: pageIndex) ?? []).sorted { $0.zIndex < $1.zIndex }) { item in
                let itemW = item.relativeWidth * proxy.size.width
                let itemH: CGFloat = if let ar = item.aspectRatio, ar > 0 { itemW / ar } else { item.relativeHeight * proxy.size.height }
                let pct = item.cornerRadius ?? 0
                let radius = min(itemW, itemH) / 2 * pct / 100
                CanvasItemView(item: item, isEditing: .constant(false))
                    .frame(width: itemW, height: itemH)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .rotationEffect(.degrees(item.rotation))
                    .opacity(item.opacity)
                    .position(
                        x: item.relativeX * proxy.size.width + itemW / 2,
                        y: item.relativeY * proxy.size.height + itemH / 2
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
                Button("Today") {
                    let now = Date()
                    currentYear = Calendar.current.component(.year, from: now)
                    let month = Calendar.current.component(.month, from: now)
                    pageIndex = (month - 1) / monthsPerPage
                }
                    .keyboardShortcut("t", modifiers: .command)

                Divider().frame(height: 16)

                // Zoom level (months per page)
                Picker("Zoom", selection: $monthsPerPage) {
                    Text("연별").tag(12)
                    Text("분기").tag(3)
                    Text("월별").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                if monthsPerPage < 12 {
                    // Page navigation
                    Button(action: { pageIndex = max(0, pageIndex - 1) }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(pageIndex <= 0)

                    Group {
                        if monthsPerPage == 1 {
                            Text(Calendar.current.shortMonthSymbols[startMonth - 1])
                        } else {
                            Text("\(startMonth)–\(startMonth + monthsPerPage - 1)")
                        }
                    }
                    .font(.body.bold().monospacedDigit())
                    .frame(minWidth: 36)

                    Button(action: { pageIndex = min(maxPageIndex, pageIndex + 1) }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(pageIndex >= maxPageIndex)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                Button(action: { collapseTopArea.toggle() }) {
                    Label("Top Area", systemImage: collapseTopArea ? "rectangle.tophalf.inset.filled" : "rectangle.topthird.inset.filled")
                }
                .help(collapseTopArea ? "상단 영역 보이기" : "상단 영역 숨기기")

                Button(action: { showCalendarFilter.toggle() }) {
                    Label("Calendars", systemImage: "calendar")
                }

                Button(action: { showFontSizePicker.toggle() }) {
                    Label("Font Size", systemImage: "textformat.size")
                }
                .popover(isPresented: $showFontSizePicker) {
                    VStack(spacing: 8) {
                        Text("Font Size: \(Int(eventFontSize))pt")
                            .font(.headline)
                        Slider(value: $eventFontSize, in: AppSettings.eventFontSizeRange, step: 1)
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

                // Canvas edit mode toggle
                Toggle(isOn: $isCanvasEditMode) {
                    Label("Canvas", systemImage: "paintbrush")
                }
                .toggleStyle(.button)
            }
        }

        if isCanvasEditMode {
            ToolbarItem(placement: .secondaryAction) {
                HStack(spacing: 4) {
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
        Button(action: { showStickerInput.toggle() }) {
            Label("Sticker", systemImage: "star.square.on.square")
        }
        .sheet(isPresented: $showStickerInput) {
            SFSymbolPicker { symbolName in
                guard let doc = currentDocument else { return }
                addCanvasItem(.newSticker(symbolName, zIndex: doc.nextZIndex))
                showStickerInput = false
            }
        }

        if !selectedCanvasItemIDs.isEmpty {
            if selectedCanvasItemIDs.count == 1 {
                Button(action: { showInspector = true }) {
                    Label("Inspector", systemImage: "slider.horizontal.3")
                }
                .help("Inspector")
            }
            Button(action: { bringSelectedToFront() }) {
                Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
            }
            .keyboardShortcut("]", modifiers: .command)
            .help("Bring to Front")

            Button(action: { sendSelectedToBack() }) {
                Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Send to Back")
        }
    }

    // MARK: - Actions

    private func navigateBack() {
        if monthsPerPage < 12 {
            if pageIndex > 0 {
                pageIndex -= 1
            } else {
                currentYear -= 1
                pageIndex = maxPageIndex
            }
        } else {
            currentYear -= 1
        }
    }

    private func navigateForward() {
        if monthsPerPage < 12 {
            if pageIndex < maxPageIndex {
                pageIndex += 1
            } else {
                currentYear += 1
                pageIndex = 0
            }
        } else {
            currentYear += 1
        }
    }


    private func reloadEvents() {
        fetchTask?.cancel()
        fetchTask = Task {
            await eventManager.fetchEvents(for: currentYear)
            guard !Task.isCancelled else { return }
            recomputeLayout()
        }
    }

    private func recomputeLayout() {
        let events = eventManager.events
        segments = EventLayoutEngine.layout(events: events, year: currentYear, maxLanes: maxEventRows)
        overflows = EventLayoutEngine.overflowCounts(events: events, year: currentYear, maxLanes: maxEventRows)
    }

    private func openEditor(startMonth: Int, startDay: Int, endMonth: Int, endDay: Int) {
        let cal = Calendar.current
        editorContext = EventEditorContext(
            startDate: cal.date(from: DateComponents(year: currentYear, month: startMonth, day: startDay)),
            endDate: cal.date(from: DateComponents(year: currentYear, month: endMonth, day: endDay))
        )
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
        Task {
            guard let result = await ImageManager.importImage(from: url),
                  let doc = currentDocument else { return }
            let item = CanvasItem.newImage(fileName: result.fileName, thumbnail: result.thumbnail, zIndex: doc.nextZIndex)
            item.zoomLevel = monthsPerPage
            item.pageIndex = pageIndex
            doc.appendItem(item)
            selectedCanvasItemIDs = [item.persistentModelID]
        }
    }


    private func addCanvasItem(_ item: CanvasItem) {
        guard let doc = currentDocument else { return }
        item.zoomLevel = monthsPerPage
        item.pageIndex = pageIndex
        doc.appendItem(item)
        selectedCanvasItemIDs = [item.persistentModelID]
    }

    private func bringSelectedToFront() {
        guard let doc = currentDocument else { return }
        for item in selectedCanvasItems {
            item.zIndex = doc.nextZIndex
        }
    }

    private func sendSelectedToBack() {
        guard let doc = currentDocument else { return }
        for item in selectedCanvasItems {
            item.zIndex = doc.minZIndex
        }
    }

    private func deleteSelectedCanvasItems() {
        let fileNames = selectedCanvasItems.compactMap(\.imageFileName)
        for item in selectedCanvasItems {
            currentDocument?.removeItem { $0.persistentModelID == item.persistentModelID }
            modelContext.delete(item)
        }
        selectedCanvasItemIDs.removeAll()
        showInspector = false
        do {
            try modelContext.save()
        } catch {
            print("Failed to save after deleting canvas items: \(error)")
            return
        }
        for fileName in fileNames {
            ImageManager.deleteImage(fileName: fileName)
        }
    }
}

struct EventEditorContext: Identifiable {
    let id = UUID()
    var existingEvent: EKEvent? = nil
    var startDate: Date? = nil
    var endDate: Date? = nil
}

#Preview {
    ContentView()
        .modelContainer(for: [YearDocument.self, CanvasItem.self, VisionBoard.self, VisionBoardItem.self], inMemory: true)
}
