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

    // 줌 범위 및 스텝
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 4.0
    private let zoomSteps: [CGFloat] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00]

    // board.items 변경 시에만 정렬 (제스처 중 body 재평가마다 sort 방지)
    @State private var sortedItems: [VisionBoardItem] = []

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
                                    clipboardManager.snapshot = CanvasItemSnapshot(from: item)
                                    clipboardManager.triggerCopyToast()
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
                // board에서 뷰포트 복원
                scale = board.viewportScale
                offsetX = board.viewportOffsetX
                offsetY = board.viewportOffsetY
                refreshSortedItems()
                setupScrollMonitor()
            }
            .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            .onDisappear {
                persistViewport()
                teardownScrollMonitor()
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
        .onDeleteCommand {
            deleteSelectedItems()
        }
        .onCopyCommand {
            guard let item = selectedItems.first else { return [] }
            clipboardManager.snapshot = CanvasItemSnapshot(from: item)
            clipboardManager.triggerCopyToast()
            return [NSItemProvider(object: "" as NSString)]
        }
        .onPasteCommand(of: [.plainText]) { _ in
            pasteItem(in: viewSize)
        }
        .onKeyPress(.delete) {
            guard !selectedItemIDs.isEmpty else { return .ignored }
            deleteSelectedItems()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard !selectedItemIDs.isEmpty else { return .ignored }
            deleteSelectedItems()
            return .handled
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            guard !selectedItemIDs.isEmpty else { return .ignored }
            selectedItemIDs.removeAll()
            showInspector = false
            return .handled
        }
    }

    // MARK: - Items Cache

    private func refreshSortedItems() {
        sortedItems = (board.items ?? []).sorted { $0.zIndex < $1.zIndex }
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
                if event.phase == .ended || event.momentumPhase == .ended {
                    persistViewport()
                }
                return event
            }

            // 일반 scroll → 패닝
            offsetX += event.scrollingDeltaX
            offsetY += event.scrollingDeltaY
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
                .disabled(currentScale <= zoomSteps.first!)
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
        let jitter = Double.random(in: -20...20)
        let itemType = CanvasItemType(rawValue: snap.type) ?? .text
        let w = snap.absoluteWidth ?? 200
        let h = snap.absoluteHeight ?? 200
        let item = VisionBoardItem(type: itemType,
                                   x: center.x - w / 2 + jitter,
                                   y: center.y - h / 2 + jitter,
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
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.0
            offsetX = 0
            offsetY = 0
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
        withAnimation(.easeOut(duration: 0.2)) {
            offsetX = cx - canvasX * newScale
            offsetY = cy - canvasY * newScale
            scale = newScale
        }
        persistViewport()
    }
}
