import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VisionBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardManager.self) private var clipboardManager
    @Bindable var board: VisionBoard

    // 실시간 뷰포트 (렌더링에 사용)
    @State private var scale: CGFloat = 1.0
    @State private var offsetX: CGFloat = 0.0
    @State private var offsetY: CGFloat = 0.0

    // 제스처 진행 중 임시 값
    @State private var gestureScale: CGFloat = 1.0
    @State private var gesturePanOffset: CGSize = .zero
    @State private var pinchOffset: CGSize = .zero
    @State private var isPinching = false


    // 선택/편집
    @State private var selectedItemIDs: Set<PersistentIdentifier> = []
    @State private var showInspector = false
    @State private var showImagePicker = false
    @State private var showStickerInput = false

    // 마키 선택
    @State private var marqueeRect: CGRect?
    @State private var isMarqueeActive = false

    // 다중 이동
    @State private var multiDragOffset: CGSize = .zero

    // 뷰 크기 (GeometryReader에서 갱신)
    @State private var viewSize: CGSize = CGSize(width: 1200, height: 800)

    // 스크롤 모니터
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?

    // 줌 범위 및 스텝
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 4.0
    private let zoomSteps: [CGFloat] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00]

    // board.items 변경 시에만 정렬 (제스처 중 body 재평가마다 sort 방지)
    @State private var sortedItems: [VisionBoardItem] = []
    // cachedWorldBounds 캐시 (아이템 변경 시에만 재계산)
    @State private var cachedWorldBounds: CGRect = .zero

    // 합산 값
    private var currentScale: CGFloat {
        clampScale(scale * gestureScale)
    }

    private var currentOffset: CGSize {
        CGSize(
            width: offsetX + gesturePanOffset.width + pinchOffset.width,
            height: offsetY + gesturePanOffset.height + pinchOffset.height
        )
    }

    /// cachedWorldBounds 재계산 (sortedItems 또는 viewSize 변경 시 호출)
    private func recalcWorldBounds() {
        let defaultRect = CGRect(
            x: -viewSize.width,
            y: -viewSize.height,
            width: viewSize.width * 3,
            height: viewSize.height * 3
        )
        guard !sortedItems.isEmpty else { cachedWorldBounds = defaultRect; return }
        var mnX = CGFloat.infinity, mnY = CGFloat.infinity
        var mxX = -CGFloat.infinity, mxY = -CGFloat.infinity
        for item in sortedItems {
            mnX = min(mnX, item.x)
            mnY = min(mnY, item.y)
            mxX = max(mxX, item.x + item.width)
            mxY = max(mxY, item.y + item.height)
        }
        let itemsBounds = CGRect(x: mnX - 200, y: mnY - 200,
                                  width: mxX - mnX + 400, height: mxY - mnY + 400)
        cachedWorldBounds = defaultRect.union(itemsBounds)
    }

    private var selectedItems: [VisionBoardItem] {
        sortedItems.filter { selectedItemIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        GeometryReader { geo in
            let visibleRect = visibleCanvasRect(viewSize: geo.size)
            ZStack {
                InfiniteCanvasBackground(scale: currentScale, offset: currentOffset)
                    .ignoresSafeArea()

                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("붙여넣기") {
                                let viewSize = viewSize
                                pasteItem(in: viewSize)
                            }
                            .disabled(clipboardManager.snapshot == nil)
                        }

                    ForEach(sortedItems) { item in
                        let isSelected = selectedItemIDs.contains(item.persistentModelID)
                        let isMultiSelected = selectedItemIDs.count > 1
                        let itemRect = CGRect(x: item.x, y: item.y,
                                              width: item.width, height: item.height)
                        if isSelected || visibleRect.intersects(itemRect) {
                            DraggableVisionBoardItem(
                                item: item,
                                scale: scale,
                                isSelected: isSelected,
                                multipleSelected: isSelected && isMultiSelected,
                                multiDragOffset: isSelected && isMultiSelected ? multiDragOffset : .zero,
                                onSelect: { addToSelection in
                                    if addToSelection {
                                        if selectedItemIDs.contains(item.persistentModelID) {
                                            selectedItemIDs.remove(item.persistentModelID)
                                        } else {
                                            selectedItemIDs.insert(item.persistentModelID)
                                        }
                                    } else {
                                        selectedItemIDs = [item.persistentModelID]
                                    }
                                },
                                showInspector: $showInspector,
                                onCopy: {
                                    let snapshot = CanvasItemSnapshot(from: item)
                                    clipboardManager.performCopy(snapshot: snapshot)
                                },
                                onPaste: {
                                    let viewSize = viewSize
                                    pasteItem(in: viewSize)
                                },
                                onDelete: { deleteItem(item) },
                                onBringToFront: { item.zIndex = board.nextZIndex; refreshSortedItems() },
                                onSendToBack: { item.zIndex = board.minZIndex; refreshSortedItems() },
                                onMoveAll: { translation in
                                    multiDragOffset = translation
                                },
                                onMoveAllEnd: { translation in
                                    let dx = translation.width
                                    let dy = translation.height
                                    for id in selectedItemIDs {
                                        if let target = sortedItems.first(where: { $0.persistentModelID == id }) {
                                            target.x += dx
                                            target.y += dy
                                        }
                                    }
                                    multiDragOffset = .zero
                                    recalcWorldBounds()
                                }
                            )
                        }
                    }

                }
                .scaleEffect(currentScale, anchor: .topLeading)
                .offset(currentOffset)
                .gesture(panGesture)

                // 마키 사각형 오버레이 (스크린 공간)
                if let rect = marqueeRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            Rectangle().stroke(Color.accentColor, lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                // 스크롤바 오버레이
                CanvasScrollBars(
                    cachedWorldBounds: cachedWorldBounds,
                    scale: currentScale,
                    offset: currentOffset,
                    viewSize: geo.size
                )

            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let canvasPoint = screenToCanvas(value.location)
                        let addToSelection = NSEvent.modifierFlags.contains(.command)
                        if let hitItem = topItem(at: canvasPoint) {
                            if addToSelection {
                                if selectedItemIDs.contains(hitItem.persistentModelID) {
                                    selectedItemIDs.remove(hitItem.persistentModelID)
                                } else {
                                    selectedItemIDs.insert(hitItem.persistentModelID)
                                }
                            } else {
                                selectedItemIDs = [hitItem.persistentModelID]
                            }
                        } else {
                            if !addToSelection {
                                selectedItemIDs.removeAll()
                            }
                        }
                    }
            )
            .simultaneousGesture(marqueeGesture)
            .onAppear {
                viewSize = geo.size
                scale = board.viewportScale
                offsetX = board.viewportOffsetX
                offsetY = board.viewportOffsetY
                refreshSortedItems()
                clampViewport()
                setupScrollMonitor()
                setupKeyMonitor()
            }
            .onChange(of: geo.size) { _, newSize in
                viewSize = newSize
                recalcWorldBounds()
                clampViewport()
            }
            .onDisappear {
                persistViewport()
                teardownScrollMonitor()
                teardownKeyMonitor()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { visionBoardToolbar }
        .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                importImage(from: url)
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers, _ in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Items Cache

    private func refreshSortedItems() {
        sortedItems = (board.items ?? []).sorted { $0.zIndex < $1.zIndex }
        recalcWorldBounds()
    }

    // MARK: - Viewport Persistence

    private func persistViewport() {
        board.viewportScale = scale
        board.viewportOffsetX = offsetX
        board.viewportOffsetY = offsetY
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isMarqueeActive else { return }
                guard !NSEvent.modifierFlags.contains(.command) else { return }
                gesturePanOffset = value.translation
            }
            .onEnded { value in
                guard !isMarqueeActive else {
                    gesturePanOffset = .zero
                    return
                }
                guard !NSEvent.modifierFlags.contains(.command) else {
                    gesturePanOffset = .zero
                    return
                }
                offsetX += value.translation.width
                offsetY += value.translation.height
                gesturePanOffset = .zero
                clampViewport()
                persistViewport()
            }
    }

    /// Cmd+Drag 마키 선택 (inner ZStack의 simultaneousGesture — 캔버스 좌표)
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard NSEvent.modifierFlags.contains(.command) else { return }
                isMarqueeActive = true
                let origin = CGPoint(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y)
                )
                let size = CGSize(
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                marqueeRect = CGRect(origin: origin, size: size)
            }
            .onEnded { _ in
                if isMarqueeActive, let rect = marqueeRect {
                    selectItems(in: rect)
                }
                marqueeRect = nil
                isMarqueeActive = false
            }
    }

    // MARK: - Hit Test

    private func topItem(at canvasPoint: CGPoint) -> VisionBoardItem? {
        for item in sortedItems.reversed() {
            let itemRect = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            if itemRect.contains(canvasPoint) {
                return item
            }
        }
        return nil
    }

    // MARK: - Marquee Selection

    private func selectItems(in screenRect: CGRect) {
        let canvasRect = CGRect(
            x: (screenRect.minX - currentOffset.width) / currentScale,
            y: (screenRect.minY - currentOffset.height) / currentScale,
            width: screenRect.width / currentScale,
            height: screenRect.height / currentScale
        )
        for item in sortedItems {
            let itemRect = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            if canvasRect.intersects(itemRect) {
                selectedItemIDs.insert(item.persistentModelID)
            }
        }
    }

    // MARK: - Event Monitors (scroll + magnify + ⌘+scroll zoom)

    private func setupScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            if event.type == .magnify {
                // 트랙패드 핀치 줌 — 입력 레이트로 부드러운 업데이트
                if event.phase == .began {
                    gestureScale = 1.0
                    isPinching = true
                }

                gestureScale = clampScale(scale * gestureScale * (1 + event.magnification)) / scale

                // 화면 중심 기준 줌 앵커링
                let ws = viewSize
                pinchOffset = CGSize(
                    width: (ws.width / 2 - offsetX) * (1 - gestureScale),
                    height: (ws.height / 2 - offsetY) * (1 - gestureScale)
                )

                if event.phase == .ended || event.phase == .cancelled {
                    let finalScale = scale * gestureScale
                    offsetX += pinchOffset.width
                    offsetY += pinchOffset.height
                    scale = finalScale
                    gestureScale = 1.0
                    pinchOffset = .zero
                    isPinching = false
                    clampViewport()
                    persistViewport()
                }
                return event
            }

            // scrollWheel 이벤트
            guard !isPinching else { return event }

            // ⌘+scroll → 줌
            if event.modifierFlags.contains(.command) {
                let delta = event.scrollingDeltaY * 0.01
                guard delta != 0 else { return event }
                let newScale = clampScale(scale * (1 + delta))
                let ws = viewSize
                let cx = ws.width / 2, cy = ws.height / 2
                let canvasX = (cx - offsetX) / scale
                let canvasY = (cy - offsetY) / scale
                offsetX = cx - canvasX * newScale
                offsetY = cy - canvasY * newScale
                scale = newScale
                clampViewport()
                if event.phase == .ended || event.momentumPhase == .ended {
                    persistViewport()
                }
                return event
            }

            // 일반 scroll → 패닝
            offsetX += event.scrollingDeltaX
            offsetY += event.scrollingDeltaY
            clampViewport()
            if event.phase == .ended || event.momentumPhase == .ended {
                persistViewport()
            }
            return event
        }
    }

    private func teardownScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Coordinate Transforms

    private func screenToCanvas(_ pt: CGPoint) -> CGPoint {
        CGPoint(
            x: (pt.x - currentOffset.width) / currentScale,
            y: (pt.y - currentOffset.height) / currentScale
        )
    }

    private func visibleCenter(in size: CGSize) -> CGPoint {
        screenToCanvas(CGPoint(x: size.width / 2, y: size.height / 2))
    }

    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, minScale), maxScale)
    }

    /// scale과 offset을 월드 바운드 내로 클램핑한 값 반환
    private func clampedViewport(scale s: CGFloat, offsetX ox: CGFloat, offsetY oy: CGFloat) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let cs = clampScale(s)
        let world = cachedWorldBounds

        let maxOX = -world.minX * cs
        let minOX = viewSize.width - world.maxX * cs
        let cx: CGFloat = minOX >= maxOX ? (maxOX + minOX) / 2 : min(max(ox, minOX), maxOX)

        let maxOY = -world.minY * cs
        let minOY = viewSize.height - world.maxY * cs
        let cy: CGFloat = minOY >= maxOY ? (maxOY + minOY) / 2 : min(max(oy, minOY), maxOY)

        return (cs, cx, cy)
    }

    /// 현재 뷰포트를 월드 바운드 내로 클램핑
    private func clampViewport() {
        let v = clampedViewport(scale: scale, offsetX: offsetX, offsetY: offsetY)
        scale = v.scale
        offsetX = v.offsetX
        offsetY = v.offsetY
    }

    /// 캔버스 좌표계 기준 현재 보이는 영역 (여유 마진 포함)
    private func visibleCanvasRect(viewSize: CGSize) -> CGRect {
        CGRect(
            x: -currentOffset.width / currentScale,
            y: -currentOffset.height / currentScale,
            width: viewSize.width / currentScale,
            height: viewSize.height / currentScale
        ).insetBy(dx: -200, dy: -200)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var visionBoardToolbar: some ToolbarContent {
        // 왼쪽: 줌 컨트롤
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 2) {
                Button(action: { stepZoomOut() }) {
                    Label("Zoom Out", systemImage: "minus")
                }
                .disabled(currentScale <= minScale + 0.001)
                .keyboardShortcut("-", modifiers: .command)

                Text("\(Int(currentScale * 100))%")
                    .monospacedDigit()
                    .frame(minWidth: 40)

                Button(action: { stepZoomIn() }) {
                    Label("Zoom In", systemImage: "plus")
                }
                .disabled(currentScale >= zoomSteps.last!)
                .keyboardShortcut("=", modifiers: .command)

                Button(action: { resetViewport() }) {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .help("뷰포트 초기화")
            }
        }

        // 가운데: 도구
        ToolbarItem(placement: .principal) {
            HStack(spacing: 4) {
                Button(action: { showImagePicker = true }) {
                    Label("Image", systemImage: "photo")
                }

                Button(action: { addText() }) {
                    Label("Text", systemImage: "textformat")
                }

                Button(action: { showStickerInput.toggle() }) {
                    Label("Sticker", systemImage: "star.square.on.square")
                }
                .sheet(isPresented: $showStickerInput) {
                    SFSymbolPicker { symbolName in
                        addSticker(symbolName)
                        showStickerInput = false
                    }
                }
            }
        }

        // 오른쪽: 선택 도구
        if !selectedItemIDs.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    if selectedItemIDs.count == 1 {
                        Button(action: { showInspector = true }) {
                            Label("Inspector", systemImage: "slider.horizontal.3")
                        }
                        .help("Inspector")
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
        }
    }

    // MARK: - Actions

    private func addText() {
        let center = visibleCenter(in: viewSize)
        let item = VisionBoardItem.newText(at: center, zIndex: board.nextZIndex)
        modelContext.insert(item)
        board.appendItem(item)
        refreshSortedItems()
        selectedItemIDs = [item.persistentModelID]
    }

    private func addSticker(_ name: String) {
        let center = visibleCenter(in: viewSize)
        let item = VisionBoardItem.newSticker(at: center, name, zIndex: board.nextZIndex)
        modelContext.insert(item)
        board.appendItem(item)
        refreshSortedItems()
        selectedItemIDs = [item.persistentModelID]
    }

    private func importImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let result = ImageManager.importImage(from: url) else { return }
        let center = visibleCenter(in: viewSize)
        let item = VisionBoardItem.newImage(at: center, fileName: result.fileName, thumbnail: result.thumbnail, zIndex: board.nextZIndex)
        modelContext.insert(item)
        board.appendItem(item)
        refreshSortedItems()
        selectedItemIDs = [item.persistentModelID]
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data = data, let image = NSImage(data: data) else { return }
                Task { @MainActor in
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try? ImageManager.jpegData(from: image, quality: 0.9)?.write(to: tempURL)
                    guard let result = ImageManager.importImage(from: tempURL) else { return }
                    let center = visibleCenter(in: CGSize(width: 1200, height: 800))
                    let item = VisionBoardItem.newImage(at: center, fileName: result.fileName, thumbnail: result.thumbnail, zIndex: board.nextZIndex)
                    modelContext.insert(item)
                    board.appendItem(item)
                    refreshSortedItems()
                    selectedItemIDs = [item.persistentModelID]
                }
            }
        }
    }

    private func pasteItem(in viewSize: CGSize) {
        guard let snap = clipboardManager.snapshot else { return }
        let center = visibleCenter(in: viewSize)
        let offset: Double = 20
        let itemType = CanvasItemType(rawValue: snap.type) ?? .text
        let w = snap.absoluteWidth ?? 200
        let h = snap.absoluteHeight ?? 200
        let item = VisionBoardItem(type: itemType,
                                   x: center.x - w / 2 + offset,
                                   y: center.y - h / 2 + offset,
                                   width: w,
                                   height: h,
                                   rotation: snap.rotation,
                                   zIndex: board.nextZIndex,
                                   opacity: snap.opacity)
        snap.applyContent(to: item)
        // 이미지 복사 시 파일을 복제하여 독립 참조 유지
        if let original = snap.imageFileName,
           let copied = ImageManager.copyImageFile(fileName: original) {
            item.imageFileName = copied
        }
        modelContext.insert(item)
        board.appendItem(item)
        refreshSortedItems()
        selectedItemIDs = [item.persistentModelID]
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                guard let item = selectedItems.first else { return event }
                let snapshot = CanvasItemSnapshot(from: item)
                clipboardManager.performCopy(snapshot: snapshot)
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                if clipboardManager.snapshot != nil {
                    pasteItem(in: viewSize)
                }
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                guard !selectedItemIDs.isEmpty else { return event }
                deleteSelectedItems()
                return nil
            }
            if event.keyCode == 53 {
                selectedItemIDs.removeAll()
                showInspector = false
                return nil
            }
            return event
        }
    }

    private func teardownKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func deleteItem(_ item: VisionBoardItem) {
        if let fileName = item.imageFileName {
            ImageManager.deleteImage(fileName: fileName)
        }
        board.removeItem { $0.persistentModelID == item.persistentModelID }
        modelContext.delete(item)
        selectedItemIDs.remove(item.persistentModelID)
        if selectedItemIDs.isEmpty {
            showInspector = false
        }
        refreshSortedItems()
    }

    private func deleteSelectedItems() {
        for item in selectedItems {
            deleteItem(item)
        }
    }

    private func bringSelectedToFront() {
        for item in selectedItems {
            item.zIndex = board.nextZIndex
        }
        refreshSortedItems()
    }

    private func sendSelectedToBack() {
        for item in selectedItems {
            item.zIndex = board.minZIndex
        }
        refreshSortedItems()
    }

    private func resetViewport() {
        let v = clampedViewport(scale: 1.0, offsetX: 0, offsetY: 0)
        withAnimation(.easeOut(duration: 0.2)) {
            scale = v.scale
            offsetX = v.offsetX
            offsetY = v.offsetY
        }
        persistViewport()
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
        let canvasX = (cx - offsetX) / scale
        let canvasY = (cy - offsetY) / scale
        let targetOX = cx - canvasX * newScale
        let targetOY = cy - canvasY * newScale
        let v = clampedViewport(scale: newScale, offsetX: targetOX, offsetY: targetOY)
        withAnimation(.easeOut(duration: 0.2)) {
            offsetX = v.offsetX
            offsetY = v.offsetY
            scale = v.scale
        }
        persistViewport()
    }
}

// MARK: - Canvas Scroll Bars

private struct CanvasScrollBars: View {
    let cachedWorldBounds: CGRect
    let scale: CGFloat
    let offset: CGSize
    let viewSize: CGSize

    private let barThickness: CGFloat = 6
    private let barMargin: CGFloat = 4
    private let minThumbLength: CGFloat = 30

    var body: some View {
        let totalW = cachedWorldBounds.width * scale
        let totalH = cachedWorldBounds.height * scale
        // 뷰포트가 전체 월드를 다 보여주면 스크롤바 불필요
        let showH = totalW > viewSize.width + 1
        let showV = totalH > viewSize.height + 1

        ZStack(alignment: .bottomTrailing) {
            Color.clear

            if showH {
                horizontalBar(totalWidth: totalW)
            }
            if showV {
                verticalBar(totalHeight: totalH)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func horizontalBar(totalWidth: CGFloat) -> some View {
        let trackWidth = viewSize.width - barMargin * 2 - (barThickness + barMargin)
        let ratio = viewSize.width / totalWidth
        let thumbW = max(minThumbLength, trackWidth * ratio)
        let scrollableRange = totalWidth - viewSize.width
        let viewportX = -(offset.width + cachedWorldBounds.minX * scale)
        let progress = scrollableRange > 0 ? viewportX / scrollableRange : 0
        let thumbX = barMargin + (trackWidth - thumbW) * clamp(progress)

        RoundedRectangle(cornerRadius: barThickness / 2)
            .fill(Color.primary.opacity(0.25))
            .frame(width: thumbW, height: barThickness)
            .position(x: thumbX + thumbW / 2, y: viewSize.height - barMargin - barThickness / 2)
    }

    @ViewBuilder
    private func verticalBar(totalHeight: CGFloat) -> some View {
        let trackHeight = viewSize.height - barMargin * 2 - (barThickness + barMargin)
        let ratio = viewSize.height / totalHeight
        let thumbH = max(minThumbLength, trackHeight * ratio)
        let scrollableRange = totalHeight - viewSize.height
        let viewportY = -(offset.height + cachedWorldBounds.minY * scale)
        let progress = scrollableRange > 0 ? viewportY / scrollableRange : 0
        let thumbY = barMargin + (trackHeight - thumbH) * clamp(progress)

        RoundedRectangle(cornerRadius: barThickness / 2)
            .fill(Color.primary.opacity(0.25))
            .frame(width: barThickness, height: thumbH)
            .position(x: viewSize.width - barMargin - barThickness / 2, y: thumbY + thumbH / 2)
    }

    private func clamp(_ v: CGFloat) -> CGFloat {
        min(max(v, 0), 1)
    }
}
