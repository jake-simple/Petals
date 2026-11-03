import AppKit
import SwiftUI
import SwiftData
import EventKit
import PDFKit

@main
struct CalendarExportChecks {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/Petals-export-checks", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Fixture"
        calendar.cgColor = CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "여행 Trip"
        event.isAllDay = true
        event.startDate = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 8))!
        event.endDate = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 11))!
        let segments = EventLayoutEngine.layout(events: [event], year: 2027, maxLanes: 7)
        let model = try ModelContainer(for: CanvasItem.self, YearDocument.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let text = CanvasItem.newText(zIndex: 1)
        text.text = "DECORATION 확인"
        text.relativeX = 0.1
        text.relativeY = 0.02
        text.relativeWidth = 0.6
        text.relativeHeight = 0.1
        model.mainContext.insert(text)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<20 { for y in 0..<20 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        let imageData = bitmap.representation(using: .png, properties: [:])!
        let image = CanvasItem.newImage(fileName: "not-on-disk.png", thumbnail: Data(), original: imageData, zIndex: 2)
        image.relativeX = 0.85
        image.relativeY = 0.03
        image.relativeWidth = 0.08
        image.relativeHeight = 0.08
        model.mainContext.insert(image)
        for months in [12, 3, 1] {
            for decorated in [false, true] {
                let theme = Theme(id: "fixture", name: "Fixture", backgroundColor: "#FFFFFF", gridLineColor: "#CCCCCC",
                                  todayLineColor: "#FF8800", monthLabelColor: "#333333", dayLabelColor: "#444444")
                let view = CalendarExportView(year: 2027, startMonth: 1, monthsShown: months, theme: theme,
                    showTodayLine: false, dimPastDates: false, collapseTopArea: false, eventFontSize: 11,
                    maxEventRows: 7, segments: segments, overflows: [:], items: decorated ? [text, image] : [],
                    size: CGSize(width: 1200, height: 800))
                let renderer = ImageRenderer(content: view.environment(\.locale, Locale(identifier: "ko")))
                renderer.scale = 3
                let data = try CalendarExporter.pdfData(renderer)
                let pdf = PDFDocument(data: data)!
                precondition(pdf.pageCount == 1)
                precondition(pdf.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 1200, height: 832))
                let content = pdf.string ?? ""
                precondition(content.contains("2027"))
                precondition(content.contains("Trip"), "Event title missing from PDF")
                precondition(content.contains("DECORATION") == decorated, "Decoration option violated")
                let name = "\(months)-\(decorated ? "decorated" : "plain")"
                try data.write(to: output.appendingPathComponent(name + ".pdf"))
                let cgImage = renderer.cgImage!
                precondition(cgImage.width == 3600 && cgImage.height == 2496)
                let rendered = NSBitmapImageRep(cgImage: cgImage)
                try rendered.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
                if decorated {
                    let pixel = rendered.colorAt(x: 3204, y: 264)!.usingColorSpace(.sRGB)!
                    let expected = NSBitmapImageRep(data: imageData)!.colorAt(x: 10, y: 10)!.usingColorSpace(.sRGB)!
                    precondition(abs(pixel.redComponent - expected.redComponent) < 0.03 &&
                                 abs(pixel.greenComponent - expected.greenComponent) < 0.03 &&
                                 abs(pixel.blueComponent - expected.blueComponent) < 0.03,
                                 "Synced original image missing from output")
                }
                let png = rendered.representation(using: .png, properties: [:])!
                try png.write(to: output.appendingPathComponent(name + ".png"))
                precondition(pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleDownToFit, autoRotate: true) != nil)
                print("PASS: \(name) PDF one-page bounds/text, PNG 3600x2496, print operation available")
            }
        }
    }
}
