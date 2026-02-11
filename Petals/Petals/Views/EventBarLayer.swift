import SwiftUI
import EventKit

struct EventBarLayer: View {
    let segments: [EventSegment]
    let overflows: [Int: [Int: Int]]
    let maxEventRows: Int
    let obfuscateText: Bool
    var startMonth: Int = 1
    var monthsShown: Int = 12
    let onEventTap: (EKEvent) -> Void
    let onEmptyTap: (Int, Int) -> Void  // (month, day)
    let onDragCreate: (Int, Int, Int, Int) -> Void  // (month, startDay, endMonth, endDay)

    @State private var dragStart: (month: Int, day: Int)?
    @State private var dragEnd: (month: Int, day: Int)?

    var body: some View {
        GeometryReader { proxy in
            let layout = CalendarLayout(size: proxy.size, monthsShown: monthsShown, startMonth: startMonth)

            Canvas { context, size in
                let barHeight = eventBarHeight(layout: layout)

                // Event bars
                for segment in segments {
                    drawBar(segment, layout: layout, barHeight: barHeight, context: &context)
                }

                // Overflow badges (+N)
                for (month, days) in overflows {
                    for (day, count) in days {
                        let origin = layout.cellOrigin(month: month, day: day)
                        let badgeY = origin.y + CGFloat(visibleEventRows) * barHeight
                        let text = context.resolve(
                            Text("+\(count)")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.secondary)
                        )
                        context.draw(text, at: CGPoint(x: origin.x + layout.cellWidth / 2, y: badgeY + 4))
                    }
                }

                // Drag selection highlight
                if let start = dragStart, let end = dragEnd {
                    let minDay = min(start.day, end.day)
                    let maxDay = max(start.day, end.day)
                    let origin = layout.cellOrigin(month: start.month, day: minDay)
                    let width = CGFloat(maxDay - minDay + 1) * layout.cellWidth
                    let rect = CGRect(x: origin.x, y: origin.y, width: width, height: layout.cellHeight)
                    context.fill(Path(rect), with: .color(.accentColor.opacity(0.2)))
                    context.stroke(Path(rect), with: .color(.accentColor), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            // Interaction overlay
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let cell = layout.cellAt(value.location) else { return }
                            if dragStart == nil {
                                if let startCell = layout.cellAt(value.startLocation) {
                                    dragStart = startCell
                                }
                            }
                            // Clamp to same month
                            if let start = dragStart {
                                dragEnd = (month: start.month, day: max(1, min(31, cell.day)))
                            }
                        }
                        .onEnded { value in
                            let distance = hypot(value.translation.width, value.translation.height)

                            if distance < 4 {
                                // Tap
                                let barHeight = eventBarHeight(layout: layout)
                                if let segment = hitTest(at: value.location, layout: layout, barHeight: barHeight) {
                                    onEventTap(segment.event)
                                } else if let cell = layout.cellAt(value.location) {
                                    onEmptyTap(cell.month, cell.day)
                                }
                            } else if let start = dragStart, let end = dragEnd {
                                let minDay = min(start.day, end.day)
                                let maxDay = max(start.day, end.day)
                                onDragCreate(start.month, minDay, start.month, maxDay)
                            }

                            dragStart = nil
                            dragEnd = nil
                        }
                )
        }
    }

    private var visibleEventRows: Int {
        switch monthsShown {
        case 6: return 4
        case 3: return max(maxEventRows - 4, 2)
        default: return 6
        }
    }

    private func eventBarHeight(layout: CalendarLayout) -> CGFloat {
        layout.cellHeight / CGFloat(visibleEventRows + 1)
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
        let fontSize = rect.height - 1
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
