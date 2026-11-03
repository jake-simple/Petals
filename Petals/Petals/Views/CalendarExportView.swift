import SwiftUI
import EventKit

/// Output deliberately excludes all interaction overlays, search and note markers.
struct CalendarExportView: View {
    let year: Int
    let startMonth: Int
    let monthsShown: Int
    let theme: Theme
    let showTodayLine: Bool
    let dimPastDates: Bool
    let collapseTopArea: Bool
    let eventFontSize: CGFloat
    let maxEventRows: Int
    let segments: [EventSegment]
    let overflows: [Int: [Int: Int]]
    let items: [CanvasItem]
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Text(String(year) + " · " + periodLabel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.eventTextColor)
                .frame(width: size.width, height: 32)
                .background(Color(hex: theme.backgroundColor))
            calendarContent
        }
    }

    private var periodLabel: String {
        let months = Calendar.current.monthSymbols
        if monthsShown == 1 { return months[startMonth - 1] }
        return months[startMonth - 1] + " – " + months[startMonth + monthsShown - 2]
    }

    private var calendarContent: some View {
        ZStack {
            Color(hex: theme.backgroundColor)
            MoodBoardBackground(gridLineColor: theme.gridLineColor)
            ZStack {
                Color(hex: theme.backgroundColor)
                CalendarGridView(year: year, theme: theme, showTodayLine: showTodayLine,
                                 eventFontSize: eventFontSize, startMonth: startMonth, monthsShown: monthsShown)
                EventBarLayer(year: year, segments: segments, overflows: overflows,
                              maxEventRows: maxEventRows, eventFontSize: eventFontSize, theme: theme,
                              startMonth: startMonth, monthsShown: monthsShown,
                              onEventTap: { _, _ in }, onEmptyTap: { _, _ in }, onNewEvent: { _, _ in },
                              onDragCreate: { _, _, _, _ in })
                if dimPastDates {
                    PastDatesVeil(year: year, theme: theme, startMonth: startMonth, monthsShown: monthsShown)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)
            .padding(.top, CalendarLayout.topInset(height: size.height, monthsShown: monthsShown, fontSize: eventFontSize, collapsed: collapseTopArea))
            .padding(.bottom, 16)
            ForEach(items.sorted { $0.zIndex < $1.zIndex }) { item in
                let width = item.relativeWidth * size.width
                let height = item.aspectRatio.map { $0 > 0 ? width / $0 : item.relativeHeight * size.height } ?? item.relativeHeight * size.height
                CanvasItemView(item: item, isEditing: .constant(false))
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: min(width, height) / 2 * (item.cornerRadius ?? 0) / 100))
                    .rotationEffect(.degrees(item.rotation))
                    .opacity(item.opacity)
                    .position(x: item.relativeX * size.width + width / 2,
                              y: item.relativeY * size.height + height / 2)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
