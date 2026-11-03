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
    @Query(sort: \PlanningBoard.createdAt) private var allPlanningBoards: [PlanningBoard]
    @AppStorage("activePlanningBoardID") private var activePlanningBoardID = ""
    @State private var showNewBoard = false
    @State private var showBoardSettings = false
    @State private var newBoardName = ""
    @State private var planningError: String?
    @Query private var allCalendarNotes: [CalendarNote]
    @Query private var syncedYearDocuments: [YearDocument]
    @State private var sidebarTab = 0
    @State private var focusedNoteDateKey: Int?
    @State private var noteFocusRequest = 0
    @State private var newNoteDate: Date?
    @State private var showNewNote = false
    @State private var calendarSize = CGSize(width: 1200, height: 800)
    @State private var includeExportDecorations = true
    @State private var isExporting = false

    private var boardNotes: [CalendarNote] {
        allCalendarNotes.filter { $0.boardID == activePlanningBoard?.id }
    }


    private var planningBoards: [PlanningBoard] { PlanningBoardProjection.visibleBoards(allPlanningBoards) }
    private var boardYearDocuments: [YearDocument] {
        syncedYearDocuments.filter { $0.boardID == activePlanningBoard?.id && $0.year == currentYear }
    }

    private var activePlanningBoard: PlanningBoard? {
        planningBoards.first { $0.id == activePlanningBoardID } ?? planningBoards.first
    }


    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("dimPastDates") private var dimPastDates = AppSettings.dimPastDatesDefault
    @AppStorage("collapseTopArea") private var collapseTopArea = false
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault
    @AppStorage("eventFontSizeYearly") private var eventFontSizeYearly = AppSettings.eventFontSizeDefault
    @AppStorage("eventFontSizeQuarterly") private var eventFontSizeQuarterly = AppSettings.eventFontSizeDefault
    @AppStorage("eventFontSizeMonthly") private var eventFontSizeMonthly = AppSettings.eventFontSizeDefault

    // Cached layout (recomputed only on data change)
    @State private var segments: [EventSegment] = []
    @State private var overflows: [Int: [Int: Int]] = [:]

    // Event state
    @State private var selectedEvent: EKEvent?
    @State private var showEventDetail = false
    @State private var eventPopoverAnchor: CGRect = .zero
    @State private var dayDetailContext: DayDetailContext?
    @State private var editorContext: EventEditorContext?
    @State private var showCalendarFilter = false
    @State private var showFontSizePicker = false
    @State private var windowContentWidth: CGFloat = 1200
    @State private var eventSearchText = ScreenshotConfig.searchText
    @State private var eventSearchPresented = false
    @FocusState private var eventSearchFocused: Bool

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
    @State private var inputScope = WindowInputScope()
    @State private var accumulatedScrollX: CGFloat = 0
    @State private var fetchTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var theme: Theme {
        let themeID = ScreenshotConfig.theme ?? activePlanningBoard?.theme ?? currentDocument?.theme ?? "minimal-light"
        return ThemeManager.shared.theme(for: themeID).resolved(for: colorScheme)
    }

    private var currentFontSize: Double {
        switch monthsPerPage {
        case 12: return eventFontSizeYearly
        case 3: return eventFontSizeQuarterly
        default: return eventFontSizeMonthly
        }
    }

    private func setCurrentFontSize(_ value: Double) {
        let clamped = max(AppSettings.eventFontSizeRange.lowerBound, min(AppSettings.eventFontSizeRange.upperBound, value))
        switch monthsPerPage {
        case 12: eventFontSizeYearly = clamped
        case 3: eventFontSizeQuarterly = clamped
        default: eventFontSizeMonthly = clamped
        }
    }

    private var selectedCanvasItems: [CanvasItem] {
        guard !selectedCanvasItemIDs.isEmpty else { return [] }
        return PlanningBoardProjection.canvasItems(in: boardYearDocuments).filter { selectedCanvasItemIDs.contains($0.persistentModelID) }
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
        .alert("New Board", isPresented: $showNewBoard) {
            TextField("Board name", text: $newBoardName)
            Button("Create") { createPlanningBoard() }
                .disabled(newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { }
        }
        .alert("Unable to Complete", isPresented: Binding(get: { planningError != nil }, set: { if !$0 { planningError = nil } })) {
            Button("OK") { planningError = nil }
        } message: { Text(planningError ?? "") }
        .sheet(isPresented: $showNewNote) {
            NewCalendarNoteView(initialDate: newNoteDate ?? Date()) { date, body in
                guard let board = activePlanningBoard else { return }
                modelContext.insert(CalendarNote(boardID: board.id, date: date, body: body))
                savePlanningChanges()
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
                currentYear = parts.year ?? currentYear
                pageIndex = ((parts.month ?? 1) - 1) / monthsPerPage
                showNotes(month: parts.month ?? 1, day: parts.day ?? 1)
            }
        }
        .sheet(isPresented: $showBoardSettings) {
            if let board = activePlanningBoard {
                PlanningBoardSettingsView(board: board, canDelete: planningBoards.count > 1,
                    onRename: { board.name = $0; board.updatedAt = Date(); savePlanningChanges() },
                    onDuplicate: { duplicatePlanningBoard(board) },
                    onDelete: { deletePlanningBoard(board) })
            }
        }
        .inspector(isPresented: Binding(
            get: { showCalendarFilter && !showVisionBoard },
            set: { showCalendarFilter = $0 }
        )) {
            VStack(spacing: 0) {
                Picker("Sidebar", selection: $sidebarTab) {
                    Text("Calendars").tag(0)
                    Text("Notes").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
                if sidebarTab == 0 {
                    CalendarFilterView(eventManager: eventManager)
                } else {
                    CalendarNotesSidebar(notes: boardNotes, focusedDateKey: focusedNoteDateKey,
                        focusRequest: noteFocusRequest, onSelect: selectCalendarNote,
                        onAdd: { newNoteDate = suggestedNoteDate; showNewNote = true })
                    .id(activePlanningBoard?.id)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowContentWidth = $0 }
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
                        setCurrentFontSize(currentFontSize + 1)
                    }
                    .keyboardShortcut("=", modifiers: .command)

                    Button("Decrease Font Size") {
                        setCurrentFontSize(currentFontSize - 1)
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
                // Dismiss the native inspector before replacing its hosting subtree.
                // Updating both in one layout pass can recursively invalidate AppKit constraints.
                if !showVisionBoard && showCalendarFilter {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { showCalendarFilter = false }
                    DispatchQueue.main.async { showVisionBoard = true }
                } else {
                    showVisionBoard.toggle()
                }
            } label: {
                Image(systemName: showVisionBoard ? "calendar" : "sparkles.rectangle.stack")
            }
            .help(showVisionBoard ? "캘린더 보기" : "화이트보드 보기")
        }
    }

    private var calendarPresentation: some View {
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
                        eventFontSize: CGFloat(currentFontSize),
                        startMonth: startMonth, monthsShown: monthsPerPage
                    )
                    .allowsHitTesting(false)

                    // Z2: Event bars
                    EventBarLayer(
                        year: currentYear,
                        segments: visibleSegments,
                        overflows: visibleOverflows,
                        maxEventRows: maxEventRows,
                        eventFontSize: CGFloat(currentFontSize),
                        theme: theme,
                        startMonth: startMonth,
                        monthsShown: monthsPerPage,
                        focusedNoteDateKey: focusedNoteDateKey,
                        searchText: eventSearchText,
                        searchMatchCounts: EventLayoutEngine.matchingDayCounts(events: eventManager.events, year: currentYear, query: eventSearchText),
                        onEventTap: { event, rect in
                            selectedEvent = event
                            eventPopoverAnchor = rect
                            showEventDetail = true
                        },
                        onEmptyTap: { month, day in
                            let cal = Calendar.current
                            let date = cal.date(from: DateComponents(year: currentYear, month: month, day: day)) ?? Date()
                            dayDetailContext = DayDetailContext(date: date)
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
                        },
                        onAddNote: { month, day in
                            newNoteDate = Calendar.current.date(from: DateComponents(year: currentYear, month: month, day: day))
                            showNewNote = true
                        }
                    )
                    .allowsHitTesting(!isCanvasEditMode)

                    CalendarNoteMarkers(year: currentYear, startMonth: startMonth, monthsShown: monthsPerPage,
                        notes: boardNotes, theme: theme, onSelect: showNotes)
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
                .sheet(item: $dayDetailContext) { ctx in
                    DayEventsPopover(
                        date: ctx.date,
                        eventManager: eventManager,
                        onSaved: { reloadEvents() }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, CalendarLayout.topInset(height: geo.size.height, monthsShown: monthsPerPage, fontSize: CGFloat(currentFontSize), collapsed: collapseTopArea))
            .padding(.bottom, 16)
            .allowsHitTesting(!isCanvasEditMode)
            // Canvas layer (편집/표시 모드 동일한 좌표계)
            Group {
                if isCanvasEditMode {
                    CanvasLayer(
                        yearDocument: currentDocument,
                        documents: boardYearDocuments,
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { calendarSize = $0 }
        .background(WindowInputScopeReader(scope: inputScope))
        .frame(minWidth: 580, minHeight: 600)
        .toolbar {
            modeToggleToolbar
            toolbarContent
        }
        .onChange(of: eventSearchPresented) { _, presented in
            guard presented else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard eventSearchPresented else { return }
                eventSearchFocused = true
            }
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
                activatePlanningBoard()
                reloadEvents()
                do { try await ImageSyncMigration.migrate(in: modelContext) }
                catch { planningError = error.localizedDescription }
            }
        }
    }

    private var calendarLifecycle: some View {
        calendarPresentation
        .onAppear {
            preparePlanningBoards()
            loadDocument(for: currentYear)
            if let existing = scrollMonitor { NSEvent.removeMonitor(existing) }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard !showVisionBoard, inputScope.contains(event) else { return event }
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !ScreenshotConfig.isActive else { return }
            Task { @MainActor in
                do { try await ImageSyncMigration.migrate(in: modelContext) }
                catch { planningError = error.localizedDescription }
            }
        }
        .onChange(of: activePlanningBoardID) { activatePlanningBoard() }
        .onChange(of: activePlanningBoard?.recordID) { activatePlanningBoard() }
        .onChange(of: activePlanningBoard?.calendarSelectionData) {
            eventManager.planningBoard = activePlanningBoard
            eventManager.applyPlanningBoardSelection()
            savePlanningChanges()
        }
        .onChange(of: planningBoards.map(\.id)) {
            if !planningBoards.contains(where: { $0.id == activePlanningBoardID }), let first = planningBoards.first {
                activePlanningBoardID = first.id
            }
            activatePlanningBoard()
        }
    }

    private var calendarBody: some View {
        calendarLifecycle
        .onChange(of: currentYear) { _, newYear in
            loadDocument(for: newYear)
            reloadEvents()
            selectedCanvasItemIDs.removeAll()
        }
        .onChange(of: monthsPerPage) { oldValue, newValue in
            changeZoom(from: oldValue, to: newValue)
        }
        .onChange(of: syncedYearDocuments.map(\.persistentModelID)) {
            loadDocument(for: currentYear)
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
        .onChange(of: eventManager.storeRevision) {
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
            ForEach(PlanningBoardProjection.canvasItems(in: boardYearDocuments, zoom: monthsPerPage, page: pageIndex)) { item in
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
        ToolbarItemGroup(placement: .navigation) {
                Menu {
                    ForEach(planningBoards) { board in
                        Button {
                            activePlanningBoardID = board.id
                        } label: {
                            if board.id == activePlanningBoard?.id {
                                Label(board.name, systemImage: "checkmark")
                            } else { Text(board.name) }
                        }
                    }
                    Divider()
                    Button("New Board…") { newBoardName = ""; showNewBoard = true }
                    Button("Board Settings…") { showBoardSettings = true }
                        .disabled(activePlanningBoard == nil)
                } label: {
                    Text(activePlanningBoard?.name ?? String(localized: "Default"))
                        .lineLimit(1)
                }
                .accessibilityIdentifier("planningBoardPicker")
                .frame(maxWidth: 160)
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

                // Zoom level (months per page)
                if windowContentWidth < 1250 {
                    zoomPicker.pickerStyle(.menu).labelsHidden().frame(width: 90)
                } else {
                    zoomPicker.pickerStyle(.segmented).frame(width: 180)
                }

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

        ToolbarItem(placement: .primaryAction) {
            Group {
                if eventSearchPresented {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search event titles", text: $eventSearchText)
                            .textFieldStyle(.plain)
                            .focused($eventSearchFocused)
                            .accessibilityIdentifier("eventTitleSearch")
                            .onExitCommand {
                                eventSearchText = ""
                                eventSearchFocused = false
                                eventSearchPresented = false
                            }
                        Button {
                            eventSearchText = ""
                            eventSearchFocused = false
                            eventSearchPresented = false
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 220)
                } else {
                    Button { eventSearchPresented = true } label: {
                        Label("Find", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("eventSearchButton")
                }
            }
            .background {
                Button("Find") { eventSearchPresented = true; eventSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Toggle("Include Decorations", isOn: $includeExportDecorations)
                    Divider()
                    Button("Export PDF…") { exportCalendar(.pdf) }
                    Button("Export PNG…") { exportCalendar(.png) }
                    Button("Print…") { exportCalendar(.print) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                .disabled(isExporting)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: String(localized: "Font Size: %lldpt"), Int(currentFontSize)))
                            .font(.headline)
                        Slider(
                            value: Binding(
                                get: { currentFontSize },
                                set: { setCurrentFontSize($0) }
                            ),
                            in: AppSettings.eventFontSizeRange,
                            step: 1
                        )
                        .frame(width: 160)
                    }
                    .padding()
                }

                // Theme picker
                Button(action: { showThemePicker.toggle() }) {
                    Label("Theme", systemImage: "paintpalette")
                }
                .popover(isPresented: $showThemePicker) {
                    ThemePickerView(
                        themes: ThemeManager.shared.themes,
                        selectedThemeID: Binding(
                            get: { activePlanningBoard?.theme ?? currentDocument?.theme ?? "minimal-light" },
                            set: { activePlanningBoard?.theme = $0; activePlanningBoard?.updatedAt = Date(); savePlanningChanges() }
                        )
                    )
                }

                // Canvas edit mode toggle
                Toggle(isOn: $isCanvasEditMode) {
                    Label("Canvas", systemImage: "paintbrush")
                }
                .toggleStyle(.button)
        }

        if isCanvasEditMode {
            ToolbarItem(placement: .secondaryAction) {
                HStack(spacing: 4) {
                    canvasToolButtons
                }
            }
        }
    }

    private var zoomPicker: some View {
        Picker("Zoom", selection: $monthsPerPage) {
            Text("연별").tag(12)
            Text("분기").tag(3)
            Text("월별").tag(1)
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
        guard let boardID = activePlanningBoard?.id else { currentDocument = nil; return }
        let descriptor = FetchDescriptor<YearDocument>(predicate: #Predicate { $0.year == year && $0.boardID == boardID })
        if let doc = (try? modelContext.fetch(descriptor))?.first {
            currentDocument = doc
        } else {
            let doc = YearDocument(year: year)
            doc.boardID = boardID
            modelContext.insert(doc)
            currentDocument = doc
        }
    }

    private func changeZoom(from oldValue: Int, to newValue: Int) {
        var month = pageIndex * oldValue + 1
        if let key = focusedNoteDateKey, key / 10000 == currentYear {
            month = key / 100 % 100
        }
        pageIndex = (min(12, max(1, month)) - 1) / newValue
        selectedCanvasItemIDs.removeAll()
    }

    private func exportCalendar(_ format: CalendarExporter.Format) {
        guard !isExporting else { return }
        isExporting = true
        let items = includeExportDecorations
            ? PlanningBoardProjection.canvasItems(in: boardYearDocuments, zoom: monthsPerPage, page: pageIndex) : []
        let output = CalendarExportView(year: currentYear, startMonth: startMonth, monthsShown: monthsPerPage,
            theme: theme, showTodayLine: showTodayLine, dimPastDates: dimPastDates,
            collapseTopArea: collapseTopArea, eventFontSize: CGFloat(currentFontSize), maxEventRows: maxEventRows,
            segments: visibleSegments, overflows: visibleOverflows, items: items, size: calendarSize)
        let name = "Petals-\(currentYear)-\(startMonth)-\(startMonth + monthsPerPage - 1)"
        Task { @MainActor in
            defer { isExporting = false }
            do { try await CalendarExporter.export(output, format: format, name: name) }
            catch { planningError = error.localizedDescription }
        }
    }

    private var suggestedNoteDate: Date {
        if let key = focusedNoteDateKey,
           let date = Calendar.current.date(from: DateComponents(year: key / 10000, month: key / 100 % 100, day: key % 100)) {
            return date
        }
        let now = Date()
        let parts = Calendar.current.dateComponents([.year, .month], from: now)
        if parts.year == currentYear, let month = parts.month,
           month >= startMonth && month < startMonth + monthsPerPage { return now }
        return Calendar.current.date(from: DateComponents(year: currentYear, month: startMonth, day: 1)) ?? now
    }

    private func showNotes(month: Int, day: Int) {
        focusedNoteDateKey = currentYear * 10000 + month * 100 + day
        noteFocusRequest += 1
        sidebarTab = 1
        showCalendarFilter = true
    }

    private func selectCalendarNote(_ note: CalendarNote) {
        currentYear = note.year
        pageIndex = (note.month - 1) / monthsPerPage
        focusedNoteDateKey = note.dateKey
    }

    private func preparePlanningBoards() {
        do {
            if ScreenshotConfig.isActive {
                if planningBoards.isEmpty {
                    let board = PlanningBoard(name: String(localized: "Default"))
                    modelContext.insert(board)
                    for index in 0..<ScreenshotConfig.noteCount {
                        let date = Calendar.current.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
                            .addingTimeInterval(Double(index / 3) * 86400)
                        let body = ScreenshotConfig.isKorean
                            ? "여행 준비 \(index + 1)\n숙소 예약과 준비물을 확인하세요."
                            : "Trip planning \(index + 1)\nCheck reservations and the packing list."
                        modelContext.insert(CalendarNote(boardID: board.id, date: date, body: body))
                    }
                    if ScreenshotConfig.noteCount > 0 { sidebarTab = 1; showCalendarFilter = true }
                    try modelContext.save()
                    activePlanningBoardID = board.id
                }
            } else {
                activePlanningBoardID = try PlanningBoardMigration.migrate(in: modelContext, calendars: eventManager.calendars)
            }
            activatePlanningBoard()
        } catch { planningError = error.localizedDescription }
    }

    private func activatePlanningBoard() {
        focusedNoteDateKey = nil
        eventManager.planningBoard = activePlanningBoard
        if !ScreenshotConfig.isActive { eventManager.applyPlanningBoardSelection() }
        loadDocument(for: currentYear)
        selectedCanvasItemIDs.removeAll()
    }

    private func savePlanningChanges() {
        do { try modelContext.save() }
        catch { planningError = error.localizedDescription }
    }

    private func createPlanningBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let board = PlanningBoard(name: name)
        modelContext.insert(board)
        do {
            try modelContext.save()
            activePlanningBoardID = board.id
            sidebarTab = 0
            showCalendarFilter = true
        } catch { planningError = error.localizedDescription }
    }

    private func duplicatePlanningBoard(_ board: PlanningBoard) {
        do {
            try modelContext.save()
            let name = String(format: String(localized: "%@ Copy"), board.name)
            let copy = try PlanningBoardOperations.duplicate(board, name: name, in: modelContext)
            activePlanningBoardID = copy.id
        } catch {
            modelContext.rollback()
            planningError = error.localizedDescription
        }
    }

    private func deletePlanningBoard(_ board: PlanningBoard) {
        guard let next = planningBoards.first(where: { $0.id != board.id }) else { return }
        do {
            try PlanningBoardOperations.delete(board, in: modelContext)
            activePlanningBoardID = next.id
        } catch { planningError = error.localizedDescription }
    }

    private func importImage(from url: URL) {
        guard let doc = currentDocument else { return }
        let targetZoom = monthsPerPage
        let targetPage = pageIndex
        Task {
            guard let result = await ImageManager.importImage(from: url) else { return }
            let item = CanvasItem.newImage(fileName: result.fileName, thumbnail: result.thumbnail, original: result.original, zIndex: doc.nextZIndex)
            item.zoomLevel = targetZoom
            item.pageIndex = targetPage
            doc.appendItem(item)
            if currentDocument === doc, monthsPerPage == targetZoom, pageIndex == targetPage {
                selectedCanvasItemIDs = [item.persistentModelID]
            }
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
            item.zIndex = (PlanningBoardProjection.canvasItems(in: boardYearDocuments).map(\.zIndex).max() ?? doc.nextZIndex) + 1
        }
    }

    private func sendSelectedToBack() {
        guard let doc = currentDocument else { return }
        for item in selectedCanvasItems {
            item.zIndex = (PlanningBoardProjection.canvasItems(in: boardYearDocuments).map(\.zIndex).min() ?? doc.minZIndex) - 1
        }
    }

    private func deleteSelectedCanvasItems() {
        let fileNames = selectedCanvasItems.compactMap(\.imageFileName)
        for item in selectedCanvasItems {
            item.yearDocument?.removeItem { $0.persistentModelID == item.persistentModelID }
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

struct DayDetailContext: Identifiable {
    let id = UUID()
    let date: Date
}

#Preview {
    ContentView()
        .modelContainer(for: [YearDocument.self, CanvasItem.self, VisionBoard.self, VisionBoardItem.self], inMemory: true)
}
