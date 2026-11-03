import SwiftUI

struct ItemImageView: View {
    let fileName: String?
    let thumbnailData: Data?
    var originalData: Data? = nil

    @State private var loadedImage: NSImage?
    @State private var thumbnailImage: NSImage?

    private var displayImage: NSImage? {
        if let originalData, let original = NSImage(data: originalData) { return original }
        if let loadedImage { return loadedImage }
        if let fileName, let cached = ImageManager.cachedImage(fileName: fileName) { return cached }
        return thumbnailImage
    }

    var body: some View {
        Group {
            if let image = displayImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.2))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .task(id: fileName) {
            loadedImage = nil
            thumbnailImage = thumbnailData.flatMap { NSImage(data: $0) }
            guard let fileName else {
                loadedImage = nil
                return
            }
            let image = await ImageManager.loadImage(fileName: fileName)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }
}
