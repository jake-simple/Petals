import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var currentYear = Calendar.current.component(.year, from: Date())
    @State private var eventManager = EventManager()
    @State private var currentDocument: YearDocument?

    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault
    @AppStorage("eventFontSize") private var eventFontSize = AppSettings.eventFontSizeDefault

    // Cached layout (recomputed only on data change)
    @State private var segments: [EventSegment] = []
    @State private var overflows: [Int: [Int: Int]] = [:]

    // Event state
    @State private var selectedEvent: EKEvent?
    @State private var showEventDetail = false
    @State private var eventPopoverAnchor: CGRect = .zero
    @State private var editorContext: EventEditorContext?
    @State private var showCalendarFilter = false
    @State private var showFontSizePicker = false

    // Viewport state (infinite zoom)
    @State private var calendarScale: CGFloat = 1.0
    @State private var calendarOffsetX: CGFloat = 0.0
    @State private var calendarOffsetY: CGFloat = 0.0
    @State private var gestureScale: CGFloat = 1.0
    @State private var pinchOffset: CGSize = .zero
    @State private var isPinching = false
    @State private var viewSize: CGSize = CGSize(width: 1200, height: 800)

    // 화이트보드 모드
    @State private var showVisionBoard = false
    @State private var selectedVisionBoardID: PersistentIdentifier?

    // Canvas state
    @State private var isCanvasEditMode = false
    @State private var selectedCanvasItemIDs: Set<PersistentIdentifier> = []
    @State private var showImagePicker = false
    @State private var showInspector = false
    @State private var showThemePicker = false
    @AppStorage("showTopArea") private var showTopArea = true
    @State private var showStickerInput = false
    @State private var scrollMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    // Zoom constants
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 10.0
    private let zoomSteps: [CGFloat] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0, 7.0, 10.0]

    private var currentScale: CGFloat {
        clampScale(calendarScale * gestureScale)
    }

    private var currentOffset: CGSize {
        CGSize(
            width: calendarOffsetX + pinchOffset.width,
            height: calendarOffsetY + pinchOffset.height
        )
    }

    private var theme: Theme {
        let themeID = currentDocument?.theme ?? "minimal-light"
        return ThemeManager.shared.theme(for: themeID).resolved(for: colorScheme)
    }

    private var selectedCanvasItems: [CanvasItem] {
        guard !selectedCanvasItemIDs.isEmpty else { return [] }
        return (currentDocument?.canvasItems ?? []).filter { selectedCanvasItemIDs.contains($0.persistentModelID) }
    }

    /// Segments split at subrow boundaries (always 12 months, daysPerRow=31).
    private var visibleSegments: [EventSegment] {
        let dpr = 31
        var result: [EventSegment] = []
        for seg in segments {
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
    }

    @ToolbarContentBuilder
    private var modeToggleToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showVisionBoard.toggle()
            } label: {
                Image(systemName: showVisionBoard ? "calendar" : "rectangle.3.group")
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

            // Scaled calendar content
            ZStack {
                // Calendar card
                ZStack {
                    Color(hex: theme.backgroundColor)

                    ZStack {
                        // Z1: Grid + today line
                        CalendarGridView(
                            year: currentYear, theme: theme, showTodayLine: showTodayLine,
                            eventFontSize: CGFloat(eventFontSize),
                            startMonth: 1, monthsShown: 12
                        )
                        .allowsHitTesting(false)

                        // Z2: Event bars
                        EventBarLayer(
                            year: currentYear,
                            segments: visibleSegments,
                            overflows: overflows,
                            maxEventRows: maxEventRows,
                            eventFontSize: CGFloat(eventFontSize),
                            startMonth: 1,
                            monthsShown: 12,
                            onEventTap: { event, rect in
                                selectedEvent = event
                                eventPopoverAnchor = rect
                                showEventDetail = true
                            },
                            onEmptyTap: { month, day in
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
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, showTopArea ? geo.size.height * 0.18 : 16)
                .padding(.bottom, 16)
                .allowsHitTesting(!isCanvasEditMode)

                // Canvas layer (편집/표시 모드 동일한 좌표계)
                Group {
                    if isCanvasEditMode {
                        CanvasLayer(
                            yearDocument: currentDocument,
                            selectedItemIDs: $selectedCanvasItemIDs,
                            showInspector: $showInspector
                        )
                    } else {
                        canvasDisplayLayer
                    }
                }
            }
            .scaleEffect(currentScale, anchor: .topLeading)
            .offset(currentOffset)
        }
        .clipped()
        .onAppear { viewSize = geo.size }
        .onChange(of: geo.size) { _, newSize in viewSize = newSize }
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
            await eventManager.requestAccess()
            reloadEvents()
        }
        .onAppear {
            loadDocument(for: currentYear)
            setupCalendarZoomMonitor()
        }
        .onDisappear {
            teardownCalendarZoomMonitor()
        }
        .onChange(of: currentYear) { _, newYear in
            loadDocument(for: newYear)
            reloadEvents()
            selectedCanvasItemIDs.removeAll()
            resetZoom()
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
    }

    // MARK: - Display-only canvas (non-edit mode)

    @ViewBuilder
    private var canvasDisplayLayer: some View {
        GeometryReader { proxy in
            ForEach((currentDocument?.canvasItems ?? []).sorted { $0.zIndex < $1.zIndex }) { item in
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
                    resetZoom()
                }
                    .keyboardShortcut("t", modifiers: .command)

                Divider().frame(height: 16)

                // Zoom controls
                Button(action: { stepZoomOut() }) {
                    Image(systemName: "minus")
                }
                .disabled(currentScale <= minScale + 0.001)
                .keyboardShortcut("-", modifiers: .command)

                Text("\(Int(currentScale * 100))%")
                    .monospacedDigit()
                    .frame(minWidth: 40)

                Button(action: { stepZoomIn() }) {
                    Image(systemName: "plus")
                }
                .disabled(currentScale >= maxScale - 0.001)
                .keyboardShortcut("=", modifiers: .command)

                Button(action: { resetZoom() }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("뷰포트 초기화")
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
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
                        Text("Font Size: \(Int(eventFontSize))pt")
                            .font(.headline)
                        Slider(value: $eventFontSize, in: 6...20, step: 1)
                            .frame(width: 160)
                    }
                    .padding()
                }

                Divider()

                Button(action: { showTopArea.toggle() }) {
                    Label("Top Area", systemImage: showTopArea ? "rectangle.topthird.inset.filled" : "rectangle.topthird.inset")
                }
                .help(showTopArea ? "상단 영역 숨기기" : "상단 영역 보이기")

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

    // MARK: - Zoom & Pan

    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, minScale), maxScale)
    }

    private func setupCalendarZoomMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            guard !showVisionBoard else { return event }

            if event.type == .magnify {
                // Trackpad pinch zoom
                if event.phase == .began {
                    gestureScale = 1.0
                    isPinching = true
                }

                gestureScale = clampScale(calendarScale * gestureScale * (1 + event.magnification)) / calendarScale

                // Anchor zoom to view center
                let ws = viewSize
                pinchOffset = CGSize(
                    width: (ws.width / 2 - calendarOffsetX) * (1 - gestureScale),
                    height: (ws.height / 2 - calendarOffsetY) * (1 - gestureScale)
                )

                if event.phase == .ended || event.phase == .cancelled {
                    let finalScale = calendarScale * gestureScale
                    calendarOffsetX += pinchOffset.width
                    calendarOffsetY += pinchOffset.height
                    calendarScale = finalScale
                    gestureScale = 1.0
                    pinchOffset = .zero
                    isPinching = false
                }
                return event
            }

            // scrollWheel
            guard !isPinching else { return event }

            // ⌘+scroll → zoom
            if event.modifierFlags.contains(.command) {
                let delta = event.scrollingDeltaY * 0.01
                guard delta != 0 else { return event }
                let newScale = clampScale(calendarScale * (1 + delta))
                let ws = viewSize
                let cx = ws.width / 2, cy = ws.height / 2
                let canvasX = (cx - calendarOffsetX) / calendarScale
                let canvasY = (cy - calendarOffsetY) / calendarScale
                calendarOffsetX = cx - canvasX * newScale
                calendarOffsetY = cy - canvasY * newScale
                calendarScale = newScale
                return event
            }

            // Regular scroll → pan
            calendarOffsetX += event.scrollingDeltaX
            calendarOffsetY += event.scrollingDeltaY
            return event
        }
    }

    private func teardownCalendarZoomMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func stepZoomIn() {
        guard let next = zoomSteps.first(where: { $0 > currentScale + 0.001 }) else { return }
        zoomToStep(next)
    }

    private func stepZoomOut() {
        guard let prev = zoomSteps.last(where: { $0 < currentScale - 0.001 }) else { return }
        zoomToStep(prev)
    }

    private func zoomToStep(_ newScale: CGFloat) {
        let ws = viewSize
        let cx = ws.width / 2, cy = ws.height / 2
        let canvasX = (cx - calendarOffsetX) / calendarScale
        let canvasY = (cy - calendarOffsetY) / calendarScale
        let targetOX = cx - canvasX * newScale
        let targetOY = cy - canvasY * newScale
        withAnimation(.easeOut(duration: 0.2)) {
            calendarOffsetX = targetOX
            calendarOffsetY = targetOY
            calendarScale = newScale
        }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            calendarScale = 1.0
            calendarOffsetX = 0
            calendarOffsetY = 0
        }
    }

    // MARK: - Actions

    private func reloadEvents() {
        eventManager.fetchEvents(for: currentYear)
        recomputeLayout()
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
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let result = ImageManager.importImage(from: url),
              let doc = currentDocument else { return }
        let item = CanvasItem.newImage(fileName: result.fileName, thumbnail: result.thumbnail, zIndex: doc.nextZIndex)
        doc.appendItem(item)
        selectedCanvasItemIDs = [item.persistentModelID]
    }


    private func addCanvasItem(_ item: CanvasItem) {
        guard let doc = currentDocument else { return }
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
        for item in selectedCanvasItems {
            if let fileName = item.imageFileName {
                ImageManager.deleteImage(fileName: fileName)
            }
            currentDocument?.removeItem { $0.persistentModelID == item.persistentModelID }
            modelContext.delete(item)
        }
        selectedCanvasItemIDs.removeAll()
        showInspector = false
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
