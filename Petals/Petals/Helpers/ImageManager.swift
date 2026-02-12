import AppKit

enum ImageManager {
    private static let maxDimension: CGFloat = 2048
    private static let thumbDimension: CGFloat = 200
    private static let thumbQuality: CGFloat = 0.6

    static var imagesDirectory: URL {
        // iCloud Drive 컨테이너 우선, 없으면 로컬 Documents
        let dir: URL
        if let icloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/Images", isDirectory: true) {
            dir = icloud
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            dir = docs.appendingPathComponent("Images", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func importImage(from url: URL) -> (fileName: String, thumbnail: Data)? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        let resized = resize(image, max: maxDimension)
        let fileName = "\(UUID().uuidString).jpg"
        guard let data = jpegData(from: resized, quality: 0.85) else { return nil }

        do {
            try data.write(to: imagesDirectory.appendingPathComponent(fileName))
        } catch { return nil }

        let thumb = resize(image, max: thumbDimension)
        guard let thumbData = jpegData(from: thumb, quality: thumbQuality) else { return nil }
        return (fileName, thumbData)
    }

    static func deleteImage(fileName: String) {
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func loadImage(fileName: String) -> NSImage? {
        let url = imagesDirectory.appendingPathComponent(fileName)
        if let image = NSImage(contentsOf: url) {
            return image
        }
        // iCloud에서 아직 다운로드되지 않은 경우 다운로드 요청
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return nil
    }

    private static func resize(_ image: NSImage, max maxDim: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDim || size.height > maxDim else { return image }
        let scale = min(maxDim / size.width, maxDim / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: newSize))
        result.unlockFocus()
        return result
    }

    static func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
