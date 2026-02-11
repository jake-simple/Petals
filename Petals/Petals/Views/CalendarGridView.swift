import SwiftUI

struct CalendarGridView: View {
    let year: Int
    let theme: Theme
    let showTodayLine: Bool

    private let calendar = Calendar.current

    var body: some View {
        Canvas { context, size in
            let layout = CalendarLayout(size: size)
            let cellWidth = layout.cellWidth
            let cellHeight = layout.cellHeight
            let rowHeight = layout.rowHeight
            let monthLabelWidth = layout.monthLabelWidth
            let perMonthLabelHeight = layout.perMonthLabelHeight

            let gridColor = Color(hex: theme.gridLineColor)
            let dayLabelColor = Color(hex: theme.dayLabelColor)
            let monthLabelColor = Color(hex: theme.monthLabelColor)
            let weekdaySymbols = calendar.veryShortStandaloneWeekdaySymbols
            let monthNames = calendar.shortMonthSymbols

            for month in 1...12 {
                let days = self.daysInMonth(month)
                let rowY = CGFloat(month - 1) * rowHeight
                let eventY = rowY + perMonthLabelHeight

                // MARK: Per-month day labels
                for day in 1...days {
                    let x = monthLabelWidth + (CGFloat(day - 1) + 0.5) * cellWidth
                    let date = makeDate(month: month, day: day)
                    let wd = calendar.component(.weekday, from: date)
                    let sym = weekdaySymbols[wd - 1]

                    let isWeekend = wd == 1 || wd == 7

                    // Day number
                    let numColor = isWeekend ? Color(hex: theme.todayLineColor).opacity(0.7) : dayLabelColor
                    let dayResolved = context.resolve(
                        Text("\(day)").font(.system(size: 9)).foregroundStyle(numColor)
                    )
                    context.draw(dayResolved, at: CGPoint(x: x, y: rowY + perMonthLabelHeight * 0.3))

                    // Weekday abbreviation
                    let wdColor = isWeekend ? Color(hex: theme.todayLineColor).opacity(0.7) : dayLabelColor.opacity(0.6)
                    let wdResolved = context.resolve(
                        Text(sym).font(.system(size: 7)).foregroundStyle(wdColor)
                    )
                    context.draw(wdResolved, at: CGPoint(x: x, y: rowY + perMonthLabelHeight * 0.72))
                }

                // MARK: Weekend + inactive cells
                for day in 1...31 {
                    let colX = monthLabelWidth + CGFloat(day - 1) * cellWidth
                    let rect = CGRect(x: colX, y: eventY, width: cellWidth, height: cellHeight)

                    if day > days {
                        context.fill(Path(rect), with: .color(Color(hex: theme.gridLineColor).opacity(0.08)))
                    } else if let weekendHex = theme.weekendColor {
                        let weekday = calendar.component(.weekday, from: makeDate(month: month, day: day))
                        if weekday == 1 || weekday == 7 {
                            context.fill(Path(rect), with: .color(Color(hex: weekendHex)))
                        }
                    }
                }

                // MARK: Month label (vertical)
                let monthY = eventY + cellHeight / 2
                let monthResolved = context.resolve(
                    Text(monthNames[month - 1])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(monthLabelColor)
                )
                context.draw(monthResolved, at: CGPoint(x: monthLabelWidth / 2, y: monthY))
            }

            // MARK: Grid lines
            // Horizontal lines: top/bottom of each month's event area
            for i in 0...12 {
                let y = CGFloat(i) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: monthLabelWidth, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }
            // Vertical lines (spanning full height)
            for i in 0...31 {
                let x = monthLabelWidth + CGFloat(i) * cellWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }

            // MARK: Today line
            if showTodayLine {
                let today = Date()
                let components = calendar.dateComponents([.year, .month, .day], from: today)
                if components.year == year, let day = components.day {
                    let x = monthLabelWidth + (CGFloat(day - 1) + 0.5) * cellWidth
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(Color(hex: theme.todayLineColor)), lineWidth: 2)
                }
            }
        }
    }

    private func daysInMonth(_ month: Int) -> Int {
        let date = makeDate(month: month, day: 1)
        return calendar.range(of: .day, in: .month, for: date)!.count
    }

    private func makeDate(month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

#Preview {
    CalendarGridView(
        year: Calendar.current.component(.year, from: Date()),
        theme: ThemeManager.shared.themes.first ?? ThemeManager.shared.theme(for: "minimal-light"),
        showTodayLine: true
    )
    .frame(width: 1100, height: 700)
}
