import Foundation
import EventKit
import SwiftData
import AppKit

@main
struct PetalsRegression {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError("FAIL: \(message)") }
        }
        let calendar = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let store = EKEventStore()
        func event(_ start: Date, _ end: Date, allDay: Bool = true) -> EKEvent {
            let event = EKEvent(eventStore: store)
            event.startDate = start
            event.endDate = end
            event.isAllDay = allDay
            return event
        }
        let annual = CalendarLayout(size: CGSize(width: 978, height: 600), year: 2026)
        check(annual.gridPosition(month: 2, day: 29) == nil, "non-leap February 29")
        check(annual.gridPosition(month: 4, day: 31) == nil, "April 31")
        check(annual.gridPosition(month: 0, day: 1) == nil, "invalid month")
        check(annual.cellAt(CGPoint(x: 903, y: 75)) == nil, "inactive February cell cannot create March event")
        check(annual.cellAt(CGPoint(x: 60, y: 600)) == nil, "bottom edge excluded")
        check(annual.cellAt(CGPoint(x: CGFloat.infinity, y: 20)) == nil, "nonfinite coordinate")
        check(CalendarLayout(size: CGSize(width: 48, height: 0)).cellAt(CGPoint(x: 48, y: 0)) == nil, "zero-sized layout")
        let leap = CalendarLayout(size: CGSize(width: 978, height: 600), year: 2024)
        check(leap.gridPosition(month: 2, day: 29) != nil, "leap day remains valid")
        for months in [1, 3, 12] {
            let layout = CalendarLayout(size: CGSize(width: 978, height: 600), monthsShown: months, year: 2024)
            for month in 1...months {
                for day in 1...layout.daysInMonth(month) {
                    let rect = layout.fullCellRect(month: month, day: day)
                    let hit = layout.cellAt(CGPoint(x: rect.midX, y: rect.midY))
                    check(hit?.month == month && hit?.day == day, "cell round trip \(months)/\(month)/\(day)")
                }
            }
        }
        let oneDay = event(date(2026, 11, 3), date(2026, 11, 4))
        let single = EventLayoutEngine.layout(events: [oneDay], year: 2026, maxLanes: 7)
        check(single.count == 1 && single[0].startDay == 3 && single[0].endDay == 3, "exclusive all-day end")
        let midnight = event(date(2026, 11, 3, 23), date(2026, 11, 4), allDay: false)
        check(EventLayoutEngine.layout(events: [midnight], year: 2026, maxLanes: 7).first?.endDay == 3, "timed midnight end")
        let dstDay = event(date(2026, 3, 8), date(2026, 3, 9))
        check(EventLayoutEngine.layout(events: [dstDay], year: 2026, maxLanes: 1).first?.endDay == 8, "all-day event across daylight-saving transition")
        let crossYear = event(date(2025, 12, 31), date(2026, 1, 1))
        check(EventLayoutEngine.layout(events: [crossYear], year: 2026, maxLanes: 7).isEmpty, "exclusive new-year boundary")
        let monthEnd = event(date(2024, 2, 28), date(2024, 3, 1))
        let feb = EventLayoutEngine.layout(events: [monthEnd], year: 2024, maxLanes: 7)
        check(feb.count == 1 && feb[0].endDay == 29, "leap month boundary")
        let zero = event(date(2026, 1, 5), date(2026, 1, 5), allDay: false)
        check(EventLayoutEngine.layout(events: [zero], year: 2026, maxLanes: 1).first?.endDay == 5, "zero-duration event stays visible")
        // The second event cannot fit on day 2 and is omitted on day 3 too.
        let overlap = [event(date(2026, 1, 1), date(2026, 1, 3)), event(date(2026, 1, 2), date(2026, 1, 4))]
        let overflow = EventLayoutEngine.overflowCounts(events: overlap, year: 2026, maxLanes: 1)
        check(overflow[1]?[2] == 1 && overflow[1]?[3] == 1, "overflow counts whole omitted span")
        check(overflow[1]?[1] == nil, "visible event has no overflow")
        check(EventLayoutEngine.layout(events: overlap, year: 2026, maxLanes: 0).isEmpty, "zero lanes")
        check(EventLayoutEngine.overflowCounts(events: overlap, year: 2026, maxLanes: 0)[1]?[2] == 2, "all events hidden at zero lanes")
        let schema = Schema([CanvasItem.self, YearDocument.self, VisionBoard.self, VisionBoardItem.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let item = CanvasItem(type: .image, relativeX: 0.2, relativeY: 0.3, relativeWidth: 0.4, relativeHeight: 0.5)
        container.mainContext.insert(item)
        item.aspectRatio = 2
        let snapshot = CanvasItemSnapshot(from: item, containerSize: CGSize(width: 1000, height: 600))
        check(snapshot.absoluteWidth == 400 && snapshot.absoluteHeight == 200, "snapshot uses rendered image dimensions")
        check(snapshot.absoluteX == 200 && snapshot.absoluteY == 180, "cross-mode group positions")
        let copy = VisionBoardItem(type: .image)
        snapshot.applyContent(to: copy)
        check(copy.aspectRatio == 2, "copy retains aspect ratio")
        copy.width = 300
        copy.height = 999
        check(CanvasItemSnapshot(from: copy).absoluteHeight == 150, "board snapshot uses rendered dimensions")
        _ = NSApplication.shared
        let firstWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let secondWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let scope = WindowInputScope()
        let view = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 100))
        firstWindow.contentView!.addSubview(view)
        scope.view = view
        func mouseEvent(window: NSWindow, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        }
        check(scope.contains(mouseEvent(window: firstWindow, x: 30, y: 30)), "input inside owning canvas")
        check(!scope.contains(mouseEvent(window: secondWindow, x: 30, y: 30)), "other window input ignored")
        check(!scope.contains(mouseEvent(window: firstWindow, x: 150, y: 150)), "sidebar/outside canvas input ignored")
        scope.view = nil
        check(!scope.isKeyWindow, "detached scope cannot handle commands")
        print("PASS: \(checks) regression assertions; no calendar events saved, in-memory model store only.")
    }
}
