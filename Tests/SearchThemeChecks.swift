import SwiftUI
import AppKit
import EventKit

@main
struct SearchThemeChecks {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let themes = try JSONDecoder().decode([Theme].self, from: Data(contentsOf: URL(fileURLWithPath: "Petals/Petals/Theme/Themes.json")))
        let testYear = Calendar.current.component(.year, from: Date()) - 1
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.cgColor = CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        let matched = EKEvent(eventStore: store)
        matched.calendar = calendar
        matched.title = "Trip 여행"
        matched.startDate = Calendar.current.date(from: DateComponents(year: testYear, month: 1, day: 4))!
        matched.endDate = Calendar.current.date(from: DateComponents(year: testYear, month: 1, day: 11))!
        let matchingDays = EventLayoutEngine.matchingDayCounts(events: [matched], year: testYear, query: "여행")
        precondition(matchingDays[1]?.count == 7 && matchingDays[1]?[4] == 1 && matchingDays[1]?[11] == nil)
        precondition(EventLayoutEngine.matchingDayCounts(events: [matched], year: testYear, query: " ").isEmpty)
        let other = EKEvent(eventStore: store)
        other.calendar = calendar
        other.title = "Meeting"
        let segments = [EventSegment(id: "a", event: matched, month: 1, startDay: 4, endDay: 10, lane: 0),
                        EventSegment(id: "b", event: other, month: 2, startDay: 4, endDay: 10, lane: 0)]
        let size = CGSize(width: 900, height: 600)
        let layout = CalendarLayout(size: size, monthsShown: 12, startMonth: 1, year: testYear)
        var count = 0
        for base in themes {
            for scheme in [ColorScheme.light, .dark] {
                let theme = base.resolved(for: scheme)
                func render(_ query: String, dimPastDates: Bool = false) -> CGImage {
                    let view = ZStack {
                        Color(hex: theme.backgroundColor)
                        let eventLayer = EventBarLayer(year: testYear, segments: segments, overflows: [:], maxEventRows: 7,
                            eventFontSize: 11, theme: theme, searchText: query,
                            onEventTap: { _, _ in }, onEmptyTap: { _, _ in }, onNewEvent: { _, _ in },
                            onDragCreate: { _, _, _, _ in })
                        eventLayer
                        if dimPastDates {
                            PastDatesVeil(year: testYear, theme: theme)
                            eventLayer.searchHighlights
                        }
                    }.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme)
                    // Render synchronously into an owned sRGB bitmap so equality checks
                    // compare a fixed pixel format, not renderer-owned provider storage.
                    let bitmap = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ImageRenderer(content: view).render { _, draw in draw(bitmap) }
                    return bitmap.makeImage()!
                }
                let before = render("")
                let a = before.dataProvider!.data! as Data
                let highlighted = render("trip")
                let b = highlighted.dataProvider!.data! as Data
                let cleared = render("  ")
                let c = cleared.dataProvider!.data! as Data
                precondition(a != b, "Match must visibly highlight: \(theme.id)")
                precondition(a == c, "Clearing must restore original image: \(theme.id)")
                let beforePixels = NSBitmapImageRep(cgImage: before)
                let afterPixels = NSBitmapImageRep(cgImage: highlighted)
                let dimmedPixels = NSBitmapImageRep(cgImage: render("trip", dimPastDates: true))
                // Matching fill overrides calendar colors; nonmatches are dimmed.
                for month in [1, 2] {
                    let origin = layout.cellOrigin(month: month, day: 9)
                    for dx in [3, 8, 12] {
                        let x = Int(origin.x) + dx
                        let y = Int(origin.y) + 6
                        if month == 1 {
                            precondition(afterPixels.colorAt(x: x, y: y) == dimmedPixels.colorAt(x: x, y: y), "Past-date veil must not dim search highlights: \(theme.id)")
                            precondition(beforePixels.colorAt(x: x, y: y) != afterPixels.colorAt(x: x, y: y), "Matching fill must change: \(theme.id)")
                        } else {
                            precondition(afterPixels.colorAt(x: x, y: y) != dimmedPixels.colorAt(x: x, y: y), "Past-date veil must still dim nonmatches: \(theme.id)")
                            precondition(beforePixels.colorAt(x: x, y: y) != afterPixels.colorAt(x: x, y: y), "Nonmatching fill must dim")
                        }
                    }
                }
                count += 1
            }
        }
        print("PASS: \(count) theme/scheme combinations: highlight visible, matched fill overridden, nonmatching fills dimmed, clear restores exact render")
    }
}
