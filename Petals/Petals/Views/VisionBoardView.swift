import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VisionBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VisionBoardItem.zIndex) private var items: [VisionBoardItem]

    // 뷰포트 영속화 (제스처 종료 시에만 저장)
    @AppStorage("visionBoard.scale") private var savedScale: Double = 1.0
    @AppStorage("visionBoard.offsetX") private var savedOffsetX: Double = 0.0
    @AppStorage("visionBoard.offsetY") private var savedOffsetY: Double = 0.0

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
    @State private var selectedItemID: PersistentIdentifier?
    @State private var showInspector = false
    @State private var showImagePicker = false
    @State private var showStickerInput = false

    // 스크롤 모니터
    @State private var scrollMonitor: Any?

    // 줌 범위 및 스텝
    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 4.0
    private let zoomSteps: [CGFloat] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00]

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

    // @Query(sort: \..zIndex) 이미 정렬 → O(1)
    private var nextZIndex: Int {
        (items.last?.zIndex ?? 0) + 1
    }

    private var minZIndex: Int {
        (items.first?.zIndex ?? 0) - 1
    }

    private var selectedItem: VisionBoardItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.persistentModelID == id }
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
                        .onTapGesture { selectedItemID = nil }

                    ForEach(items) { item in
                        let itemRect = CGRect(x: item.x, y: item.y,
                                              width: item.width, height: item.height)
                        if item.persistentModelID == selectedItemID
                            || visibleRect.intersects(itemRect) {
                            DraggableVisionBoardItem(
                                item: item,
                                scale: scale,
                                isSelected: item.persistentModelID == selectedItemID,
                                onSelect: { selectedItemID = item.persistentModelID },
                                showInspector: $showInspector,
                                onDelete: { deleteItem(item) },
                                onBringToFront: { item.zIndex = nextZIndex },
                                onSendToBack: { item.zIndex = minZIndex }
                            )
                        }
                    }
                }
                .scaleEffect(currentScale, anchor: .topLeading)
                .offset(currentOffset)
                .gesture(panGesture)
            }
            .onAppear {
                // AppStorage → State 복원
                scale = savedScale
                offsetX = savedOffsetX
                offsetY = savedOffsetY
                setupScrollMonitor()
            }
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
            guard let item = selectedItem else { return }
            deleteItem(item)
        }
        .onKeyPress(.delete) {
            guard selectedItemID != nil else { return .ignored }
            if let item = selectedItem { deleteItem(item) }
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard selectedItemID != nil else { return .ignored }
            if let item = selectedItem { deleteItem(item) }
            return .handled
        }
        .focusable()
        .focusEffectDisabled()
    }

    // MARK: - Viewport Persistence

    private func persistViewport() {
        savedScale = scale
        savedOffsetX = offsetX
        savedOffsetY = offsetY
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                gesturePanOffset = value.translation
            }
            .onEnded { value in
                offsetX += value.translation.width
                offsetY += value.translation.height
                gesturePanOffset = .zero
                persistViewport()
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
                let ws = NSApp.keyWindow?.contentLayoutRect.size ?? CGSize(width: 1200, height: 800)
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
                let ws = NSApp.keyWindow?.contentLayoutRect.size ?? CGSize(width: 1200, height: 800)
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
        if selectedItemID != nil {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    Button(action: { showInspector = true }) {
                        Label("Inspector", systemImage: "slider.horizontal.3")
                    }
                    .help("Inspector")

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
        let center = visibleCenter(in: NSScreen.main.map { CGSize(width: $0.frame.width, height: $0.frame.height) } ?? CGSize(width: 1200, height: 800))
        let item = VisionBoardItem.newText(at: center, zIndex: nextZIndex)
        modelContext.insert(item)
        selectedItemID = item.persistentModelID
    }

    private func addSticker(_ name: String) {
        let center = visibleCenter(in: NSScreen.main.map { CGSize(width: $0.frame.width, height: $0.frame.height) } ?? CGSize(width: 1200, height: 800))
        let item = VisionBoardItem.newSticker(at: center, name, zIndex: nextZIndex)
        modelContext.insert(item)
        selectedItemID = item.persistentModelID
    }

    private func importImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let result = ImageManager.importImage(from: url) else { return }
        let center = visibleCenter(in: NSScreen.main.map { CGSize(width: $0.frame.width, height: $0.frame.height) } ?? CGSize(width: 1200, height: 800))
        let item = VisionBoardItem.newImage(at: center, fileName: result.fileName, thumbnail: result.thumbnail, zIndex: nextZIndex)
        modelContext.insert(item)
        selectedItemID = item.persistentModelID
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
                    let item = VisionBoardItem.newImage(at: center, fileName: result.fileName, thumbnail: result.thumbnail, zIndex: nextZIndex)
                    modelContext.insert(item)
                    selectedItemID = item.persistentModelID
                }
            }
        }
    }

    private func deleteItem(_ item: VisionBoardItem) {
        if let fileName = item.imageFileName {
            ImageManager.deleteImage(fileName: fileName)
        }
        modelContext.delete(item)
        if selectedItemID == item.persistentModelID {
            selectedItemID = nil
            showInspector = false
        }
    }

    private func bringSelectedToFront() {
        guard let item = selectedItem else { return }
        item.zIndex = nextZIndex
    }

    private func sendSelectedToBack() {
        guard let item = selectedItem else { return }
        item.zIndex = minZIndex
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
        let ws = NSApp.keyWindow?.contentLayoutRect.size ?? CGSize(width: 1200, height: 800)
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
