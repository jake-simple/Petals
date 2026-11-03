import SwiftUI
import UniformTypeIdentifiers
import PDFKit

@MainActor
enum CalendarExporter {
    enum Format { case pdf, png, print }

    static func export(_ view: CalendarExportView, format: Format, name: String) async throws {
        // ImageRenderer does not run asynchronous view tasks. Preload originals,
        // and fail explicitly instead of silently exporting blurry thumbnails.
        for item in view.items where item.type == CanvasItemType.image.rawValue {
            if let data = item.originalImageData, NSImage(data: data) != nil { continue }
            guard let file = item.imageFileName,
                  await ImageManager.loadImage(fileName: file) != nil else {
                throw ExportError.imageUnavailable
            }
        }
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: view.size.width, height: view.size.height + 32)
        renderer.scale = 3
        if format == .png {
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw ExportError.renderFailed
            }
            try save(data, type: .png, name: name)
        } else {
            let data = try pdfData(renderer)
            if format == .pdf {
                try save(data, type: .pdf, name: name)
            } else {
                guard let document = PDFDocument(data: data),
                      let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
                    throw ExportError.renderFailed
                }
                operation.showsPrintPanel = true
                operation.showsProgressPanel = true
                operation.run()
            }
        }
    }

    static func pdfData<V: View>(_ renderer: ImageRenderer<V>) throws -> Data {
        let output = NSMutableData()
        var succeeded = false
        renderer.render(rasterizationScale: 3) { size, draw in
            var bounds = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: output),
                  let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            succeeded = true
        }
        guard succeeded else { throw ExportError.renderFailed }
        return output as Data
    }

    private static func save(_ data: Data, type: UTType, name: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name + "." + (type.preferredFilenameExtension ?? "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }

    enum ExportError: LocalizedError {
        case imageUnavailable, renderFailed
        var errorDescription: String? {
            switch self {
            case .imageUnavailable: String(localized: "An original image is not downloaded yet. Try again after iCloud finishes downloading.")
            case .renderFailed: String(localized: "The calendar could not be rendered.")
            }
        }
    }
}
