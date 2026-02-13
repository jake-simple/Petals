import SwiftUI
import EventKit

struct EventBarLayer: View {
    let year: Int
    let segments: [EventSegment]
    let overflows: [Int: [Int: Int]]
    let maxEventRows: Int
    let obfuscateText: Bool
    let eventFontSize: CGFloat
    var startMonth: Int = 1
    var monthsShown: Int = 12
    let onEventTap: (EKEvent, CGRect) -> Void
    let onEmptyTap: (Int, Int) -> Void  // (month, day)
    let onDragCreate: (Int, Int, Int, Int) -> Void  // (startMonth, startDay, endMonth, endDay)
    var onEventDelete: ((EKEvent, EKSpan) -> Void)?

    @State private var dragStart: (month: Int, day: Int)?
    @State private var dragEnd: (month: Int, day: Int)?
    @State private var selectedCell: (month: Int, day: Int)?
    @State private var lastTapTime: Date?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let layout = CalendarLayout(size: proxy.size, monthsShown: monthsShown, startMonth: startMonth)

            Canvas { context, size in
                let barHeight = eventBarHeight(layout: layout)
                let rows = visibleEventRows(layout: layout)

                // Event bars (skip lanes beyond visible rows)
                for segment in segments where segment.lane < rows {
                    drawBar(segment, layout: layout, barHeight: barHeight, context: &context)
                }

                // Merge hidden segments into overflow counts
                var badgeCounts: [Int: [Int: Int]] = [:]
                for segment in segments where segment.lane >= rows {
                    for day in segment.startDay...segment.endDay {
                        badgeCounts[segment.month, default: [:]][day, default: 0] += 1
                    }
                }
                for (month, days) in overflows {
                    for (day, count) in days {
                        badgeCounts[month, default: [:]][day, default: 0] += count
                    }
                }

                // Overflow badges (+N)
                for (month, days) in badgeCounts {
                    for (day, count) in days {
                        let origin = layout.cellOrigin(month: month, day: day)
                        let badgeY = origin.y + CGFloat(rows) * barHeight
                        let remainingHeight = layout.cellHeight - CGFloat(rows) * barHeight
                        let text = context.resolve(
                            Text("+\(count)")
                                .font(.system(size: eventFontSize - 2, weight: .medium))
                                .foregroundStyle(.secondary)
                        )
                        context.draw(text, at: CGPoint(x: origin.x + layout.cellWidth / 2, y: badgeY + remainingHeight * 0.4))
                    }
                }

                // Selected cell border (includes day label area)
                if let sel = selectedCell, dragStart == nil {
                    let origin = layout.cellOrigin(month: sel.month, day: sel.day)
                    let rect = CGRect(x: origin.x, y: origin.y - layout.perMonthLabelHeight,
                                      width: layout.cellWidth, height: layout.rowHeight)
                    context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(.accentColor), lineWidth: 2)
                }

                // Drag selection highlight (includes day label area)
                if let start = dragStart, let end = dragEnd,
                   start.month != end.month || start.day != end.day {
                    let cal = Calendar.current
                    let isStartFirst = start.month < end.month || (start.month == end.month && start.day <= end.day)
                    let first = isStartFirst ? start : end
                    let last = isStartFirst ? end : start

                    var m = first.month
                    var d = first.day
                    while m < last.month || (m == last.month && d <= last.day) {
                        guard m >= 1, m <= 12 else { break }
                        let dim = cal.range(of: .day, in: .month,
                            for: cal.date(from: DateComponents(year: year, month: m, day: 1))!)!.count
                        if d > dim { m += 1; d = 1; continue }

                        let subrow = (d - 1) / layout.daysPerRow
                        let lastInSubrow = min(dim, (subrow + 1) * layout.daysPerRow)
                        let segEnd = (m == last.month) ? min(last.day, lastInSubrow) : lastInSubrow

                        let origin = layout.cellOrigin(month: m, day: d)
                        let width = CGFloat(segEnd - d + 1) * layout.cellWidth
                        let rect = CGRect(x: origin.x, y: origin.y - layout.perMonthLabelHeight,
                                          width: width, height: layout.rowHeight)
                        context.fill(Path(rect), with: .color(.accentColor.opacity(0.2)))
                        context.stroke(Path(rect), with: .color(.accentColor), lineWidth: 1)

                        if segEnd >= dim { m += 1; d = 1 } else { d = segEnd + 1 }
                    }
                }
            }
            .allowsHitTesting(false)

            // Interaction overlay
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverLocation = location
                    case .ended:
                        hoverLocation = nil
                    @unknown default:
                        break
                    }
                }
                .contextMenu {
                    if let loc = hoverLocation,
                       let segment = hitTest(at: loc, layout: layout, barHeight: eventBarHeight(layout: layout)) {
                        if segment.event.hasRecurrenceRules {
                            Button(role: .destructive) {
                                onEventDelete?(segment.event, .thisEvent)
                            } label: {
                                Label("This Event Only", systemImage: "trash")
                            }
                            Button(role: .destructive) {
                                onEventDelete?(segment.event, .futureEvents)
                            } label: {
                                Label("All Future Events", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                onEventDelete?(segment.event, .thisEvent)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let cell = layout.cellAt(value.location) else { return }
                            if dragStart == nil {
                                if let startCell = layout.cellAt(value.startLocation) {
                                    dragStart = startCell
                                }
                            }
                            if dragStart != nil {
                                dragEnd = cell
                            }
                        }
                        .onEnded { value in
                            let distance = hypot(value.translation.width, value.translation.height)

                            if distance < 4 {
                                // Tap
                                let barHeight = eventBarHeight(layout: layout)
                                if let segment = hitTest(at: value.location, layout: layout, barHeight: barHeight) {
                                    let rect = barRect(for: segment, layout: layout, barHeight: barHeight)
                                    selectedCell = nil
                                    onEventTap(segment.event, rect)
                                } else if let cell = layout.cellAt(value.location) {
                                    let now = Date()
                                    if let sel = selectedCell, sel.month == cell.month, sel.day == cell.day,
                                       let last = lastTapTime, now.timeIntervalSince(last) < 0.4 {
                                        // Double tap → create event
                                        selectedCell = nil
                                        lastTapTime = nil
                                        onEmptyTap(cell.month, cell.day)
                                    } else {
                                        // Single tap → select
                                        selectedCell = cell
                                        lastTapTime = now
                                    }
                                }
                            } else if let start = dragStart, let end = dragEnd {
                                let isStartFirst = start.month < end.month || (start.month == end.month && start.day <= end.day)
                                let first = isStartFirst ? start : end
                                let last = isStartFirst ? end : start
                                onDragCreate(first.month, first.day, last.month, last.day)
                            }

                            dragStart = nil
                            dragEnd = nil
                        }
                )
        }
    }

    private func visibleEventRows(layout: CalendarLayout) -> Int {
        let barHeight = eventFontSize + 2
        return max(1, min(Int(layout.cellHeight / barHeight), maxEventRows))
    }

    private func eventBarHeight(layout: CalendarLayout) -> CGFloat {
        eventFontSize + 2
    }

    private func barRect(for segment: EventSegment, layout: CalendarLayout, barHeight: CGFloat) -> CGRect {
        let origin = layout.cellOrigin(month: segment.month, day: segment.startDay)
        let width = CGFloat(segment.endDay - segment.startDay + 1) * layout.cellWidth
        return CGRect(
            x: origin.x,
            y: origin.y + CGFloat(segment.lane) * barHeight,
            width: width,
            height: barHeight - 1
        )
    }

    private func drawBar(_ segment: EventSegment, layout: CalendarLayout,
                         barHeight: CGFloat, context: inout GraphicsContext) {
        let rect = barRect(for: segment, layout: layout, barHeight: barHeight)
        let color = Color(cgColor: segment.event.calendar.cgColor)

        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))

        // Title text (clipped to bar)
        let title = obfuscateText ? "●●●●" : (segment.event.title ?? "")
        let fontSize = eventFontSize
        guard fontSize >= 3 else { return }
        context.drawLayer { ctx in
            ctx.clip(to: Path(rect))
            let text = ctx.resolve(
                Text(title)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.white)
            )
            ctx.draw(text, at: CGPoint(x: rect.minX + 2, y: rect.midY), anchor: .leading)
        }
    }

    private func hitTest(at point: CGPoint, layout: CalendarLayout, barHeight: CGFloat) -> EventSegment? {
        for segment in segments.reversed() {
            if barRect(for: segment, layout: layout, barHeight: barHeight).contains(point) {
                return segment
            }
        }
        return nil
    }
}
