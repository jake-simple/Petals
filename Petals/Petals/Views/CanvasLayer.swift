import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CanvasLayer: View {
    @Environment(\.modelContext) private var modelContext
    var yearDocument: YearDocument?
    var zoomLevel: Int = 12
    @Binding var selectedItemID: PersistentIdentifier?
    @Binding var showInspector: Bool

    @State private var clipboard: CanvasItemSnapshot?

    private var sortedItems: [CanvasItem] {
        (yearDocument?.canvasItems(for: zoomLevel) ?? []).sorted { $0.zIndex < $1.zIndex }
    }

    private var selectedItem: CanvasItem? {
        guard let id = selectedItemID else { return nil }
        return sortedItems.first { $0.persistentModelID == id }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selectedItemID = nil }

                ForEach(sortedItems) { item in
                    DraggableCanvasItem(
                        item: item,
                        containerSize: proxy.size,
                        isSelected: item.persistentModelID == selectedItemID,
                        onSelect: { selectedItemID = item.persistentModelID },
                        showInspector: $showInspector,
                        onDelete: { deleteItem(item) },
                        onBringToFront: { bringToFront(item) },
                        onSendToBack: { sendToBack(item) }
                    )
                }
            }
        }
        .onDrop(of: [.image], isTargeted: nil) { providers, location in
            handleDrop(providers: providers)
            return true
        }
        .onDeleteCommand {
            guard let item = selectedItem else { return }
            deleteItem(item)
        }
        .onCopyCommand {
            guard let item = selectedItem else { return [] }
            clipboard = CanvasItemSnapshot(from: item)
            return []
        }
        .onPasteCommand(of: [.plainText]) { _ in
            pasteItem()
        }
    }

    private func deleteItem(_ item: CanvasItem) {
        if let fileName = item.imageFileName {
            ImageManager.deleteImage(fileName: fileName)
        }
        yearDocument?.removeItem { $0.persistentModelID == item.persistentModelID }
        modelContext.delete(item)
        if selectedItemID == item.persistentModelID { selectedItemID = nil }
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
        guard let snap = clipboard, let doc = yearDocument else { return }
        let itemType = CanvasItemType(rawValue: snap.type) ?? .text
        let item = CanvasItem(type: itemType,
                              relativeX: snap.relativeX + 0.02,
                              relativeY: snap.relativeY + 0.02,
                              relativeWidth: snap.relativeWidth,
                              relativeHeight: snap.relativeHeight,
                              rotation: snap.rotation,
                              opacity: snap.opacity,
                              zoomLevel: zoomLevel)
        item.imageFileName = snap.imageFileName
        item.thumbnailData = snap.thumbnailData
        item.text = snap.text
        item.fontSize = snap.fontSize
        item.fontName = snap.fontName
        item.textColor = snap.textColor
        item.textAlignment = snap.textAlignment
        item.isBold = snap.isBold
        item.isItalic = snap.isItalic
        item.stickerName = snap.stickerName
        item.shapeType = snap.shapeType
        item.fillColor = snap.fillColor
        item.strokeColor = snap.strokeColor
        item.strokeWidth = snap.strokeWidth
        item.zIndex = doc.nextZIndex
        doc.appendItem(item)
        selectedItemID = item.persistentModelID
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
                    doc.appendItem(item)
                    selectedItemID = item.persistentModelID
                }
            }
        }
    }
}
