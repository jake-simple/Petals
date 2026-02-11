import SwiftUI

struct CalendarGridView: View {
    let year: Int
    let theme: Theme
    let showTodayLine: Bool
    var startMonth: Int = 1
    var monthsShown: Int = 12

    private let calendar = Calendar.current

    var body: some View {
        Canvas { context, size in
            let layout = CalendarLayout(size: size, monthsShown: monthsShown, startMonth: startMonth)
            let cellWidth = layout.cellWidth
            let cellHeight = layout.cellHeight
            let rowHeight = layout.rowHeight
            let monthLabelWidth = layout.monthLabelWidth
            let perMonthLabelHeight = layout.perMonthLabelHeight
            let daysPerRow = layout.daysPerRow
            let rowsPerMonth = layout.rowsPerMonth
            let totalRows = layout.totalRows

            let gridColor = Color(hex: theme.gridLineColor)
            let dayLabelColor = Color(hex: theme.dayLabelColor)
            let monthLabelColor = Color(hex: theme.monthLabelColor)
            let weekdaySymbols = calendar.veryShortStandaloneWeekdaySymbols
            let monthNames = calendar.shortMonthSymbols

            let endMonth = startMonth + monthsShown - 1

            for month in startMonth...endMonth {
                let days = self.daysInMonth(month)
                let monthOffset = month - startMonth

                for subrow in 0..<rowsPerMonth {
                    let visualRow = monthOffset * rowsPerMonth + subrow
                    let rowY = CGFloat(visualRow) * rowHeight
                    let eventY = rowY + perMonthLabelHeight

                    let firstDay = subrow * daysPerRow + 1
                    let lastDay = min((subrow + 1) * daysPerRow, 31)

                    // MARK: Per-subrow day labels
                    for day in firstDay...lastDay where day <= days {
                        let col = day - firstDay
                        let x = monthLabelWidth + (CGFloat(col) + 0.5) * cellWidth
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
                    for day in firstDay...lastDay {
                        let col = day - firstDay
                        let colX = monthLabelWidth + CGFloat(col) * cellWidth
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

                    // MARK: Month label (only on first subrow, vertically centered across all subrows)
                    if subrow == 0 {
                        let totalMonthHeight = CGFloat(rowsPerMonth) * rowHeight
                        let monthY = rowY + totalMonthHeight / 2
                        let monthResolved = context.resolve(
                            Text(monthNames[month - 1])
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(monthLabelColor)
                        )
                        context.draw(monthResolved, at: CGPoint(x: monthLabelWidth / 2, y: monthY))
                    }
                }
            }

            // MARK: Grid lines
            // Horizontal lines
            for i in 0...totalRows {
                let y = CGFloat(i) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: monthLabelWidth, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }
            // Vertical lines
            for i in 0...daysPerRow {
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
                if components.year == year,
                   let todayMonth = components.month,
                   let day = components.day,
                   todayMonth >= startMonth, todayMonth < startMonth + monthsShown {
                    let col = (day - 1) % daysPerRow
                    let subrow = (day - 1) / daysPerRow
                    let monthOffset = todayMonth - startMonth
                    let visualRow = monthOffset * rowsPerMonth + subrow
                    let x = monthLabelWidth + (CGFloat(col) + 0.5) * cellWidth
                    let rowTop = CGFloat(visualRow) * rowHeight
                    let rowBottom = rowTop + rowHeight
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: rowTop))
                    path.addLine(to: CGPoint(x: x, y: rowBottom))
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
