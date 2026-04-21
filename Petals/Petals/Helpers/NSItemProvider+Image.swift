import AppKit
import UniformTypeIdentifiers

extension NSItemProvider {
    func loadImageData() async -> Data? {
        await withCheckedContinuation { cont in
            _ = loadDataRepresentation(for: .image) { data, _ in
                cont.resume(returning: data)
            }
        }
    }
}
