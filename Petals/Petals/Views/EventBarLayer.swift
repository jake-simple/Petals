import SwiftUI
import EventKit

struct EventBarLayer: View {
    let year: Int
    let segments: [EventSegment]
    let overflows: [Int: [Int: Int]]
    let maxEventRows: Int
    let eventFontSize: CGFloat
    let theme: Theme
    var startMonth: Int = 1
    var monthsShown: Int = 12
    var focusedNoteDateKey: Int? = nil
    var searchText: String = ""
    var searchMatchCounts: [Int: [Int: Int]] = [:]
    let onEventTap: (EKEvent, CGRect) -> Void
    let onEmptyTap: (Int, Int) -> Void  // (month, day) — 더블탭: 그날 일정 시트
    let onNewEvent: (Int, Int) -> Void  // (month, day) — 우클릭 메뉴: 새 이벤트
    let onDragCreate: (Int, Int, Int, Int) -> Void  // (startMonth, startDay, endMonth, endDay)
    var onEventDelete: ((EKEvent, EKSpan) -> Void)?
    var onAddNote: ((Int, Int) -> Void)?

    @State private var dragStart: (month: Int, day: Int)?
    @State private var dragEnd: (month: Int, day: Int)?
    @State private var selectedCell: (month: Int, day: Int)?
    @State private var lastTapTime: Date?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let layout = CalendarLayout(size: proxy.size, monthsShown: monthsShown, startMonth: startMonth, year: year)

            Canvas { context, size in
                let barHeight = eventBarHeight(layout: layout)
                let rows = visibleEventRows(layout: layout)

                // Event bars (skip lanes beyond visible rows)
                for segment in segments where segment.lane < rows {
                    drawBar(segment, layout: layout, barHeight: barHeight, context: context)
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

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                var visibleMatchCounts: [Int: [Int: Int]] = [:]
                if !query.isEmpty {
                    for segment in segments where segment.lane < rows && (segment.event.title ?? "").localizedStandardContains(query) {
                        for day in segment.startDay...segment.endDay {
                            visibleMatchCounts[segment.month, default: [:]][day, default: 0] += 1
                        }
                    }
                }

                // Overflow badges (+N)
                for (month, days) in badgeCounts {
                    for (day, count) in days {
                        let origin = layout.cellOrigin(month: month, day: day)
                        let hasHiddenMatch = (searchMatchCounts[month]?[day] ?? 0) > (visibleMatchCounts[month]?[day] ?? 0)
                        let text = context.resolve(
                            Text("+\(count)")
                                .font(.system(size: eventFontSize - 2, weight: hasHiddenMatch ? .bold : .medium))
                                .foregroundStyle(theme.eventTextColor.opacity(hasHiddenMatch ? 1 : 0.65))
                        )
                        if layout.weekdayMode {
                            // 분기/월별: 날짜 숫자 바로 왼쪽
                            let dayText = context.resolve(CalendarGridView.dayNumberText(day, fontSize: eventFontSize))
                            let dayWidth = dayText.measure(in: CGSize(width: layout.cellWidth, height: layout.perMonthLabelHeight)).width
                            let badgeX = origin.x + layout.cellWidth - CalendarLayout.dayLabelInset - dayWidth - 4
                            context.draw(text, at: CGPoint(x: badgeX, y: origin.y - layout.perMonthLabelHeight * 0.5), anchor: .trailing)
                        } else {
                            // Annual cells are too narrow to share the date-label strip.
                            // Reserve a footer independent of the search state.
                            context.draw(text, at: CGPoint(x: origin.x + 3, y: origin.y + layout.cellHeight - overflowFooterHeight * 0.5), anchor: .leading)
                        }
                    }
                }

                // Selected cell border (includes day label area)
                if let sel = selectedCell, dragStart == nil {
                    let rect = layout.fullCellRect(month: sel.month, day: sel.day)
                    context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(.accentColor), lineWidth: 2)
                }

                // Drag selection highlight (includes day label area)
                if let start = dragStart, let end = dragEnd,
                   start.month != end.month || start.day != end.day {
                    let isStartFirst = start.month < end.month || (start.month == end.month && start.day <= end.day)
                    let first = isStartFirst ? start : end
                    let last = isStartFirst ? end : start

                    for m in first.month...last.month where m >= 1 && m <= 12 {
                        let dim = layout.daysInMonth(m)
                        let sDay = (m == first.month) ? first.day : 1
                        let eDay = (m == last.month) ? min(last.day, dim) : dim
                        guard sDay <= eDay else { continue }

                        for run in layout.rowRuns(month: m, startDay: sDay, endDay: eDay) {
                            let origin = layout.cellOrigin(month: m, day: run.startDay)
                            let width = CGFloat(run.endDay - run.startDay + 1) * layout.cellWidth
                            let rect = CGRect(x: origin.x, y: origin.y - layout.perMonthLabelHeight,
                                              width: width, height: layout.rowHeight)
                            context.fill(Path(rect), with: .color(.accentColor.opacity(0.2)))
                            context.stroke(Path(rect), with: .color(.accentColor), lineWidth: 1)
                        }
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
                    if let loc = hoverLocation {
                        if let cell = layout.cellAt(loc) {
                            Button { onAddNote?(cell.month, cell.day) } label: {
                                Label("Add Note", systemImage: "note.text.badge.plus")
                            }
                            Divider()
                        }
                        if let segment = hitTest(at: loc, layout: layout, barHeight: eventBarHeight(layout: layout)) {
                            Button(role: .destructive) {
                                onEventDelete?(segment.event, .thisEvent)
                            } label: {
                                Label(segment.event.hasRecurrenceRules ? "This Event Only" : "Delete", systemImage: "trash")
                            }
                            if segment.event.hasRecurrenceRules {
                                Button(role: .destructive) {
                                    onEventDelete?(segment.event, .futureEvents)
                                } label: {
                                    Label("All Future Events", systemImage: "trash")
                                }
                            }
                        } else if let cell = layout.cellAt(loc) {
                            Button {
                                onNewEvent(cell.month, cell.day)
                            } label: {
                                Label("새 이벤트", systemImage: "plus")
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
                                        // Double tap → 그날 일정 시트
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
        .onChange(of: focusedNoteDateKey, initial: true) { _, key in
            guard let key, key / 10000 == year else {
                selectedCell = nil
                return
            }
            selectedCell = (month: key / 100 % 100, day: key % 100)
        }
    }

    private var overflowFooterHeight: CGFloat { max(10, eventFontSize) }

    private func visibleEventRows(layout: CalendarLayout) -> Int {
        let barHeight = eventFontSize + 2
        let availableHeight = layout.cellHeight - (layout.weekdayMode ? 0 : overflowFooterHeight)
        return max(layout.weekdayMode ? 1 : 0, min(Int(availableHeight / barHeight), maxEventRows))
    }

    private func eventBarHeight(layout: CalendarLayout) -> CGFloat {
        eventFontSize + 2
    }

    private func barRect(for segment: EventSegment, layout: CalendarLayout, barHeight: CGFloat) -> CGRect {
        let origin = layout.cellOrigin(month: segment.month, day: segment.startDay)
        let spanDays = CGFloat(segment.endDay - segment.startDay + 1)
        let width = spanDays * layout.cellWidth
        let hInset: CGFloat = 1
        let adjustedWidth = max(0, width - hInset * 2)
        let y = origin.y + CGFloat(segment.lane) * barHeight
        return CGRect(x: origin.x + hInset, y: y, width: adjustedWidth, height: barHeight - 1)
    }

    private func drawBar(_ segment: EventSegment, layout: CalendarLayout,
                         barHeight: CGFloat, context: GraphicsContext) {
        var context = context
        let rect = barRect(for: segment, layout: layout, barHeight: barHeight)
        let color = Color(cgColor: segment.event.calendar.cgColor)

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMatch = !query.isEmpty && (segment.event.title ?? "").localizedStandardContains(query)
        if !query.isEmpty && !isMatch { context.opacity *= 0.3 }
        let fill = isMatch ? Color(hex: "#FFD84D") : color.opacity(0.4)
        let textColor = isMatch ? Color.black : theme.eventTextColor.opacity(0.78)
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(fill))

        // Title text (clipped to bar)
        let title = segment.event.title ?? ""
        let fontSize = eventFontSize
        guard fontSize >= 3 else { return }
        context.drawLayer { ctx in
            ctx.clip(to: Path(rect))
            let text = ctx.resolve(
                Text(title)
                    .font(.system(size: fontSize, weight: isMatch ? .semibold : .regular))
                    .foregroundStyle(textColor)
            )
            ctx.draw(text, at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading)
        }
    }

    private func hitTest(at point: CGPoint, layout: CalendarLayout, barHeight: CGFloat) -> EventSegment? {
        for segment in segments.reversed() where segment.lane < visibleEventRows(layout: layout) {
            if barRect(for: segment, layout: layout, barHeight: barHeight).contains(point) {
                return segment
            }
        }
        return nil
    }
}
