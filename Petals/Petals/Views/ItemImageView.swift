import SwiftUI

struct ItemImageView: View {
    let fileName: String?
    let thumbnailData: Data?

    @State private var loadedImage: NSImage?
    @State private var thumbnailImage: NSImage?

    private var displayImage: NSImage? {
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
            // 같은 fileName 이면 thumbnail 도 동일하므로 함께 키잉. Data 비교는 불안정해서 피함.
            thumbnailImage = thumbnailData.flatMap { NSImage(data: $0) }
            guard let fileName else {
                loadedImage = nil
                return
            }
            loadedImage = await ImageManager.loadImage(fileName: fileName)
        }
    }
}
