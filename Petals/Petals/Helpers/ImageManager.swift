import AppKit

nonisolated enum ImageManager {
    private static let maxDimension: CGFloat = 2048
    private static let thumbDimension: CGFloat = 200
    private static let thumbQuality: CGFloat = 0.6

    // NSCache 자체는 thread-safe. Sendable 추론 회피용으로 unsafe 명시.
    nonisolated(unsafe) private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        return cache
    }()

    static let imagesDirectory: URL = {
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
    }()

    /// 파일 URL에서 import. security-scoped resource 접근도 내부에서 관리.
    static func importImage(from url: URL) async -> (fileName: String, thumbnail: Data)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(contentsOf: url) else { return nil }
            return processImport(from: image)
        }.value
    }

    /// 원본 데이터(NSImage가 지원하는 포맷)에서 import.
    static func importImage(from data: Data) async -> (fileName: String, thumbnail: Data)? {
        await Task.detached(priority: .userInitiated) {
            guard let image = NSImage(data: data) else { return nil }
            return processImport(from: image)
        }.value
    }

    private static func processImport(from image: NSImage) -> (fileName: String, thumbnail: Data)? {
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

    static func copyImageFile(fileName: String) -> String? {
        let src = imagesDirectory.appendingPathComponent(fileName)
        let ext = (fileName as NSString).pathExtension
        let newName = "\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
        let dst = imagesDirectory.appendingPathComponent(newName)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            return newName
        } catch { return nil }
    }

    static func deleteImage(fileName: String) {
        imageCache.removeObject(forKey: fileName as NSString)
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// NSCache hit 만 동기적으로 조회. disk read 없음. 플레이스홀더 깜빡임 방지용.
    static func cachedImage(fileName: String) -> NSImage? {
        imageCache.object(forKey: fileName as NSString)
    }

    /// 캐시 조회 후 miss 시 백그라운드에서 디스크 로드. main thread blocking 없음.
    static func loadImage(fileName: String) async -> NSImage? {
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        return await Task.detached(priority: .userInitiated) {
            let url = imagesDirectory.appendingPathComponent(fileName)
            if let image = NSImage(contentsOf: url) {
                imageCache.setObject(image, forKey: key)
                return image
            }
            // iCloud에서 아직 다운로드되지 않은 경우 다운로드 요청
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }.value
    }

    private static func resize(_ image: NSImage, max maxDim: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDim || size.height > maxDim else { return image }
        let scale = min(maxDim / size.width, maxDim / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    static func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
