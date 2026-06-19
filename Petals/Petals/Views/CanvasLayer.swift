import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CanvasLayer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardManager.self) private var clipboardManager
    @Environment(PremiumStore.self) private var premium
    var yearDocument: YearDocument?
    var zoomLevel: Int = 12
    var pageIndex: Int = 0
    @Binding var selectedItemIDs: Set<PersistentIdentifier>
    @Binding var showInspector: Bool
    var onRequestPaywall: () -> Void = {}

    @State private var containerSize: CGSize = CGSize(width: 900, height: 600)
    @State private var marqueeRect: CGRect?
    @State private var isMarqueeActive = false
    @State private var multiDragOffset: CGSize = .zero

    private var sortedItems: [CanvasItem] {
        (yearDocument?.canvasItems(for: zoomLevel, pageIndex: pageIndex) ?? []).sorted { $0.zIndex < $1.zIndex }
    }

    private var selectedItems: [CanvasItem] {
        sortedItems.filter { selectedItemIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("붙여넣기") { handlePaste() }
                            .disabled(!clipboardManager.hasPasteableContent)
                    }

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
                        onCopy: { copyItems(actedOn: item, containerSize: proxy.size) },
                        onPaste: { handlePaste() },
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
                        let addToSelection = NSEvent.modifierFlags.contains(.command)
                        if let hitItem = topItem(at: value.location, containerSize: proxy.size) {
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
            .onAppear { containerSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in containerSize = newSize }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers, location in
            handleDrop(providers: providers)
            return true
        }
        .modifier(CanvasKeyCommands(
            selectedItemIDs: $selectedItemIDs,
            showInspector: $showInspector,
            onDelete: { deleteSelectedItems() },
            onCopy: {
                let snaps = selectedItems.map { CanvasItemSnapshot(from: $0, containerSize: containerSize) }
                clipboardManager.performCopy(snapshots: snaps)
            },
            onPaste: { handlePaste() }
        ))
    }

    // MARK: - Marquee Gesture

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
                    selectItems(in: rect, containerSize: containerSize)
                }
                marqueeRect = nil
                isMarqueeActive = false
            }
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
        let fileName = item.imageFileName
        yearDocument?.removeItem { $0.persistentModelID == item.persistentModelID }
        modelContext.delete(item)
        selectedItemIDs.remove(item.persistentModelID)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save after deleting canvas item: \(error)")
            return
        }
        if let fileName { ImageManager.deleteImage(fileName: fileName) }
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

    /// 우클릭 복사: 우클릭한 아이템이 다중 선택에 포함돼 있으면 선택 전체를, 아니면 그 아이템만 복사.
    private func copyItems(actedOn item: CanvasItem, containerSize size: CGSize) {
        let targets = selectedItemIDs.contains(item.persistentModelID) && selectedItemIDs.count > 1
            ? selectedItems : [item]
        let snaps = targets.map { CanvasItemSnapshot(from: $0, containerSize: size) }
        clipboardManager.performCopy(snapshots: snaps)
    }

    private func handlePaste() {
        if clipboardManager.shouldUseSystemPasteboard {
            pasteFromSystem()
        } else {
            pasteSnapshots(clipboardManager.snapshots)
        }
    }

    /// 내부 복사한 스냅샷들을 상대 배치를 유지한 채 붙여넣는다.
    private func pasteSnapshots(_ snaps: [CanvasItemSnapshot]) {
        guard let doc = yearDocument, !snaps.isEmpty else { return }
        // 무료: 텍스트 외(이미지/스티커/도형)가 하나라도 있으면 차단
        if !premium.isPremium && snaps.contains(where: { CanvasItemType(rawValue: $0.type) != .text }) {
            onRequestPaywall()
            return
        }
        let offset = 0.02
        var nextZ = doc.nextZIndex
        var newIDs: Set<PersistentIdentifier> = []
        for snap in snaps {
            let itemType = CanvasItemType(rawValue: snap.type) ?? .text
            let relW = (snap.absoluteWidth ?? snap.relativeWidth * containerSize.width) / containerSize.width
            let relH = (snap.absoluteHeight ?? snap.relativeHeight * containerSize.height) / containerSize.height
            let baseX = min(max(snap.relativeX + offset, 0), 0.95)
            let baseY = min(max(snap.relativeY + offset, 0), 0.95)
            let item = CanvasItem(type: itemType,
                                  relativeX: baseX,
                                  relativeY: baseY,
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
            item.zIndex = nextZ
            nextZ += 1
            doc.appendItem(item)
            newIDs.insert(item.persistentModelID)
        }
        selectedItemIDs = newIDs
    }

    /// 다른 앱에서 복사한 시스템 클립보드의 이미지/텍스트를 붙여넣는다.
    private func pasteFromSystem() {
        // 이미지 우선
        if let image = clipboardManager.systemImage(), let data = image.tiffRepresentation {
            guard premium.isPremium else { onRequestPaywall(); return }
            Task { @MainActor in
                guard let result = await ImageManager.importImage(from: data),
                      let doc = yearDocument else { return }
                let item = CanvasItem.newImage(fileName: result.fileName, thumbnail: result.thumbnail, zIndex: doc.nextZIndex)
                item.zoomLevel = zoomLevel
                item.pageIndex = pageIndex
                doc.appendItem(item)
                selectedItemIDs = [item.persistentModelID]
            }
            return
        }
        // 텍스트 (무료 사용자도 허용)
        if let str = clipboardManager.systemString(), let doc = yearDocument {
            let item = CanvasItem.newText(zIndex: doc.nextZIndex)
            item.text = str
            item.zoomLevel = zoomLevel
            item.pageIndex = pageIndex
            doc.appendItem(item)
            selectedItemIDs = [item.persistentModelID]
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        // 무료: 이미지 드래그앤드랍 차단
        guard premium.isPremium else {
            onRequestPaywall()
            return
        }
        for provider in providers {
            Task { @MainActor in
                guard let data = await provider.loadImageData(),
                      let result = await ImageManager.importImage(from: data),
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

