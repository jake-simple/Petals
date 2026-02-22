import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CanvasLayer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardManager.self) private var clipboardManager
    var yearDocument: YearDocument?
    var zoomLevel: Int = 12
    var pageIndex: Int = 0
    @Binding var selectedItemIDs: Set<PersistentIdentifier>
    @Binding var showInspector: Bool

    @State private var containerSize: CGSize = CGSize(width: 900, height: 600)
    @State private var marqueeRect: CGRect?
    @State private var multiDragOffset: CGSize = .zero
    @State private var keyMonitor: Any?

    private var sortedItems: [CanvasItem] {
        (yearDocument?.canvasItems(for: zoomLevel, pageIndex: pageIndex) ?? []).sorted { $0.zIndex < $1.zIndex }
    }

    private var selectedItems: [CanvasItem] {
        sortedItems.filter { selectedItemIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("붙여넣기") { pasteItem() }
                            .disabled(clipboardManager.snapshot == nil)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
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
                                if let rect = marqueeRect {
                                    let addToSelection = NSEvent.modifierFlags.contains(.command)
                                    if !addToSelection {
                                        selectedItemIDs.removeAll()
                                    }
                                    selectItems(in: rect, containerSize: proxy.size)
                                }
                                marqueeRect = nil
                            }
                    )

                ForEach(sortedItems) { item in
                    let isSelected = selectedItemIDs.contains(item.persistentModelID)
                    let isMultiSelected = selectedItemIDs.count > 1
                    DraggableCanvasItem(
                        item: item,
                        containerSize: proxy.size,
                        isSelected: isSelected,
                        multipleSelected: isSelected && isMultiSelected,
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
                            let snapshot = CanvasItemSnapshot(from: item, containerSize: proxy.size)
                            clipboardManager.performCopy(snapshot: snapshot)
                        },
                        onPaste: { pasteItem() },
                        onDelete: { deleteItem(item) },
                        onBringToFront: { bringToFront(item) },
                        onSendToBack: { sendToBack(item) },
                        onMoveAll: { translation in
                            multiDragOffset = translation
                        },
                        onMoveAllEnd: { translation in
                            let dx = translation.width / proxy.size.width
                            let dy = translation.height / proxy.size.height
                            for id in selectedItemIDs {
                                if let target = sortedItems.first(where: { $0.persistentModelID == id }) {
                                    target.relativeX += dx
                                    target.relativeY += dy
                                }
                            }
                            multiDragOffset = .zero
                        },
                        multiDragOffset: isSelected && isMultiSelected ? multiDragOffset : .zero
                    )
                }

                // 마키 사각형 오버레이
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
                        let loc = value.location
                        let addToSelection = NSEvent.modifierFlags.contains(.command)
                        if let hitItem = topItem(at: loc, containerSize: proxy.size) {
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
            .onAppear { containerSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in containerSize = newSize }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers, location in
            handleDrop(providers: providers)
            return true
        }
        .onAppear { setupKeyMonitor() }
        .onDisappear { teardownKeyMonitor() }
    }

    // MARK: - Hit Test

    private func topItem(at point: CGPoint, containerSize: CGSize) -> CanvasItem? {
        for item in sortedItems.reversed() {
            let x = item.relativeX * containerSize.width
            let y = item.relativeY * containerSize.height
            let w = item.relativeWidth * containerSize.width
            let h: CGFloat
            if let ar = item.aspectRatio, ar > 0 {
                h = w / ar
            } else {
                h = item.relativeHeight * containerSize.height
            }
            if CGRect(x: x, y: y, width: w, height: h).contains(point) {
                return item
            }
        }
        return nil
    }

    // MARK: - Marquee Selection

    private func selectItems(in rect: CGRect, containerSize: CGSize) {
        for item in sortedItems {
            let itemX = item.relativeX * containerSize.width
            let itemY = item.relativeY * containerSize.height
            let itemW = item.relativeWidth * containerSize.width
            let itemH: CGFloat
            if let ar = item.aspectRatio, ar > 0 {
                itemH = itemW / ar
            } else {
                itemH = item.relativeHeight * containerSize.height
            }
            let itemRect = CGRect(x: itemX, y: itemY, width: itemW, height: itemH)
            if rect.intersects(itemRect) {
                selectedItemIDs.insert(item.persistentModelID)
            }
        }
    }

    // MARK: - Actions

    private func deleteItem(_ item: CanvasItem) {
        if let fileName = item.imageFileName {
            ImageManager.deleteImage(fileName: fileName)
        }
        yearDocument?.removeItem { $0.persistentModelID == item.persistentModelID }
        modelContext.delete(item)
        selectedItemIDs.remove(item.persistentModelID)
    }

    private func deleteSelectedItems() {
        for item in selectedItems {
            deleteItem(item)
        }
    }

    private func bringToFront(_ item: CanvasItem) {
        guard let doc = yearDocument else { return }
        item.zIndex = doc.nextZIndex
    }

    private func sendToBack(_ item: CanvasItem) {
        guard let doc = yearDocument else { return }
        item.zIndex = doc.minZIndex
    }

    private func pasteItem() {
        guard let snap = clipboardManager.snapshot, let doc = yearDocument else { return }
        let itemType = CanvasItemType(rawValue: snap.type) ?? .text
        let relW = (snap.absoluteWidth ?? snap.relativeWidth * containerSize.width) / containerSize.width
        let relH = (snap.absoluteHeight ?? snap.relativeHeight * containerSize.height) / containerSize.height
        let item = CanvasItem(type: itemType,
                              relativeX: 0.4 + Double.random(in: -0.02...0.02),
                              relativeY: 0.4 + Double.random(in: -0.02...0.02),
                              relativeWidth: relW,
                              relativeHeight: relH,
                              rotation: snap.rotation,
                              opacity: snap.opacity,
                              zoomLevel: zoomLevel,
                              pageIndex: pageIndex)
        snap.applyContent(to: item)
        // 이미지 복사 시 파일을 복제하여 독립 참조 유지
        if let original = snap.imageFileName,
           let copied = ImageManager.copyImageFile(fileName: original) {
            item.imageFileName = copied
        }
        item.zIndex = doc.nextZIndex
        doc.appendItem(item)
        selectedItemIDs = [item.persistentModelID]
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                guard let item = selectedItems.first else { return event }
                let snapshot = CanvasItemSnapshot(from: item, containerSize: containerSize)
                clipboardManager.performCopy(snapshot: snapshot)
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                if clipboardManager.snapshot != nil {
                    pasteItem()
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

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data = data, let image = NSImage(data: data) else { return }
                Task { @MainActor in
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try? ImageManager.jpegData(from: image, quality: 0.9)?.write(to: tempURL)
                    guard let result = ImageManager.importImage(from: tempURL),
                          let doc = yearDocument else { return }
                    let item = CanvasItem.newImage(fileName: result.fileName, thumbnail: result.thumbnail, zIndex: doc.nextZIndex)
                    item.zoomLevel = zoomLevel
                    item.pageIndex = pageIndex
                    doc.appendItem(item)
                    selectedItemIDs = [item.persistentModelID]
                }
            }
        }
    }
}
