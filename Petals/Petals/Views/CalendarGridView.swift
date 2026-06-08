import SwiftUI

struct CalendarGridView: View {
    let year: Int
    let theme: Theme
    let showTodayLine: Bool
    let eventFontSize: CGFloat
    var startMonth: Int = 1
    var monthsShown: Int = 12

    private let calendar = Calendar.current

    var body: some View {
        Canvas { context, size in
            let layout = CalendarLayout(size: size, monthsShown: monthsShown, startMonth: startMonth, year: year)
            if layout.weekdayMode {
                drawWeekdayMode(context: &context, size: size, layout: layout)
            } else {
                drawYearMode(context: &context, size: size, layout: layout)
            }
            if showTodayLine {
                drawTodayHighlight(context: &context, layout: layout)
            }
        }
    }

    /// 날짜 숫자 Text (분기/월 셀, 연별 라벨, +N 배지 폭 측정이 모두 같은 폰트를 공유).
    static func dayNumberText(_ day: Int, fontSize: CGFloat) -> Text {
        Text("\(day)").font(.system(size: fontSize, weight: .semibold))
    }

    private func drawTodayHighlight(context: inout GraphicsContext, layout: CalendarLayout) {
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        guard components.year == year,
              let todayMonth = components.month, let day = components.day,
              todayMonth >= startMonth, todayMonth < startMonth + monthsShown,
              let pos = layout.gridPosition(month: todayMonth, day: day) else { return }
        let x = layout.monthLabelWidth + CGFloat(pos.col) * layout.cellWidth
        let y = layout.headerHeight + CGFloat(pos.row) * layout.rowHeight
        let rect = CGRect(x: x, y: y, width: layout.cellWidth, height: layout.rowHeight)
        context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(Color(hex: theme.todayLineColor)), lineWidth: 2)
    }

    // MARK: - Weekday mode (분기/월)

    private func drawWeekdayMode(context: inout GraphicsContext, size: CGSize, layout: CalendarLayout) {
        let cellWidth = layout.cellWidth
        let rowHeight = layout.rowHeight
        let monthLabelWidth = layout.monthLabelWidth
        let labelStrip = layout.perMonthLabelHeight
        let headerHeight = layout.headerHeight
        let totalRows = layout.totalRows

        let gridColor = Color(hex: theme.gridLineColor)
        let dayLabelColor = Color(hex: theme.dayLabelColor)
        let monthLabelColor = Color(hex: theme.monthLabelColor)
        let sundayAccent = Color(hex: theme.todayLineColor)
        let saturdayAccent = Color(hex: "3B82F6")
        // col 0 = 일요일(강조색), col 6 = 토요일(파란색), 그 외 기본색
        func weekdayColor(_ col: Int) -> Color {
            col == 0 ? sundayAccent.opacity(0.8) : (col == 6 ? saturdayAccent.opacity(0.8) : dayLabelColor)
        }

        var locCal = calendar
        locCal.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        let weekdaySymbols = locCal.veryShortStandaloneWeekdaySymbols   // index 0 = 일요일
        let monthNames = locCal.shortMonthSymbols

        // MARK: Weekday header (일~토)
        for col in 0..<7 {
            let x = monthLabelWidth + (CGFloat(col) + 0.5) * cellWidth
            let color = weekdayColor(col)
            let resolved = context.resolve(
                Text(weekdaySymbols[col])
                    .font(.system(size: eventFontSize, weight: .medium))
                    .foregroundStyle(color)
            )
            context.draw(resolved, at: CGPoint(x: x, y: headerHeight * 0.5))
        }

        // MARK: Cells (weekend shading, inactive cells, day numbers, month labels)
        let weekendShade = theme.weekendColor.map { Color(hex: $0).opacity(0.5) }
        let inactiveShade = gridColor.opacity(0.08)
        for info in layout.months {
            for subrow in 0..<info.weeks {
                let visualRow = info.startRow + subrow
                let rowY = headerHeight + CGFloat(visualRow) * rowHeight
                for col in 0..<7 {
                    let day = subrow * 7 + col - info.firstWeekdayIndex + 1
                    let colX = monthLabelWidth + CGFloat(col) * cellWidth
                    let active = day >= 1 && day <= info.daysInMonth

                    guard active else {
                        let rect = CGRect(x: colX, y: rowY, width: cellWidth, height: rowHeight)
                        context.fill(Path(rect), with: .color(inactiveShade))
                        continue
                    }

                    let isWeekend = col == 0 || col == 6
                    if isWeekend, let weekendShade {
                        let rect = CGRect(x: colX, y: rowY, width: cellWidth, height: rowHeight)
                        context.fill(Path(rect), with: .color(weekendShade))
                    }

                    let numColor = weekdayColor(col)
                    let resolved = context.resolve(Self.dayNumberText(day, fontSize: eventFontSize).foregroundStyle(numColor))
                    context.draw(resolved, at: CGPoint(x: colX + cellWidth - CalendarLayout.dayLabelInset, y: rowY + labelStrip * 0.5), anchor: .trailing)
                }
            }

            // Month label on the left, centered across the month's rows.
            let monthMidY = headerHeight + (CGFloat(info.startRow) + CGFloat(info.weeks) / 2) * rowHeight
            let monthResolved = context.resolve(
                Text(monthNames[info.month - 1])
                    .font(.system(size: eventFontSize + 1, weight: .semibold))
                    .foregroundStyle(monthLabelColor)
            )
            context.draw(monthResolved, at: CGPoint(x: monthLabelWidth / 2, y: monthMidY))
        }

        // MARK: Grid lines
        let boundaryColor = dayLabelColor.opacity(0.3)
        let boundaryStyle: (Color, CGFloat) = (boundaryColor, 0.9)
        let normalStyle: (Color, CGFloat) = (gridColor.opacity(0.6), 0.5)
        let monthBoundaryRows = Set(layout.months.map { $0.startRow })

        for i in 0...totalRows {
            let isBoundary = i == 0 || i == totalRows || monthBoundaryRows.contains(i)
            let (color, width) = isBoundary ? boundaryStyle : normalStyle
            var path = Path()
            let y = headerHeight + CGFloat(i) * rowHeight
            path.move(to: CGPoint(x: isBoundary ? 0 : monthLabelWidth, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(color), lineWidth: width)
        }
        for i in 0...7 {
            let (color, width) = (i == 0 || i == 7) ? boundaryStyle : normalStyle
            var path = Path()
            let x = monthLabelWidth + CGFloat(i) * cellWidth
            path.move(to: CGPoint(x: x, y: headerHeight))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(color), lineWidth: width)
        }
    }

    // MARK: - Year mode (연별)

    private func drawYearMode(context: inout GraphicsContext, size: CGSize, layout: CalendarLayout) {
        let cellWidth = layout.cellWidth
        let cellHeight = layout.cellHeight
        let rowHeight = layout.rowHeight
        let monthLabelWidth = layout.monthLabelWidth
        let perMonthLabelHeight = layout.perMonthLabelHeight
        let totalRows = layout.totalRows

        let gridColor = Color(hex: theme.gridLineColor)
        let dayLabelColor = Color(hex: theme.dayLabelColor)
        let monthLabelColor = Color(hex: theme.monthLabelColor)
        var locCal = calendar
        locCal.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en")
        let weekdaySymbols = locCal.veryShortStandaloneWeekdaySymbols
        let monthNames = locCal.shortMonthSymbols

        let endMonth = startMonth + monthsShown - 1

        for month in startMonth...endMonth {
            let days = layout.daysInMonth(month)
            let monthOffset = month - startMonth
            let visualRow = monthOffset
            let rowY = CGFloat(visualRow) * rowHeight
            let eventY = rowY + perMonthLabelHeight

            // Day labels (우측 정렬)
            for day in 1...31 where day <= days {
                let col = day - 1
                let colX = monthLabelWidth + CGFloat(col) * cellWidth
                let date = makeDate(month: month, day: day)
                let wd = calendar.component(.weekday, from: date)
                let sym = weekdaySymbols[wd - 1]
                // 일요일(강조색), 토요일(파란색), 그 외 기본색
                let weekendAccent: Color? = wd == 1 ? Color(hex: theme.todayLineColor) : (wd == 7 ? Color(hex: "3B82F6") : nil)
                let numColor = weekendAccent?.opacity(0.7) ?? dayLabelColor
                let wdColor = weekendAccent?.opacity(0.7) ?? dayLabelColor.opacity(0.6)
                let label = Self.dayNumberText(day, fontSize: eventFontSize).foregroundStyle(numColor)
                    + Text(" \(sym)").font(.system(size: eventFontSize)).foregroundStyle(wdColor)
                let resolved = context.resolve(label)
                context.draw(resolved, at: CGPoint(x: colX + cellWidth - CalendarLayout.dayLabelInset, y: rowY + perMonthLabelHeight * 0.5), anchor: .trailing)
            }

            // Weekend + inactive cells
            for day in 1...31 {
                let col = day - 1
                let colX = monthLabelWidth + CGFloat(col) * cellWidth
                let rect = CGRect(x: colX, y: eventY, width: cellWidth, height: cellHeight)
                if day > days {
                    context.fill(Path(rect), with: .color(Color(hex: theme.gridLineColor).opacity(0.08)))
                } else if let weekendHex = theme.weekendColor {
                    let weekday = calendar.component(.weekday, from: makeDate(month: month, day: day))
                    if weekday == 1 || weekday == 7 {
                        context.fill(Path(rect), with: .color(Color(hex: weekendHex).opacity(0.5)))
                    }
                }
            }

            // Month label
            let monthY = rowY + rowHeight / 2
            let monthResolved = context.resolve(
                Text(monthNames[month - 1])
                    .font(.system(size: eventFontSize + 1, weight: .semibold))
                    .foregroundStyle(monthLabelColor)
            )
            context.draw(monthResolved, at: CGPoint(x: monthLabelWidth / 2, y: monthY))
        }

        // Grid lines
        let boundaryColor = Color(hex: theme.dayLabelColor).opacity(0.3)
        let boundaryStyle: (Color, CGFloat) = (boundaryColor, 0.9)

        for i in 0...totalRows where i != 0 {
            var path = Path()
            let y = CGFloat(i) * rowHeight
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(boundaryStyle.0), lineWidth: boundaryStyle.1)
        }
        let normalStyle: (Color, CGFloat) = (gridColor.opacity(0.6), 0.5)
        for i in 0...31 {
            let (color, width) = i == 0 ? boundaryStyle : normalStyle
            var path = Path()
            let x = monthLabelWidth + CGFloat(i) * cellWidth
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(color), lineWidth: width)
        }
    }

    private func makeDate(month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

#Preview {
    CalendarGridView(
        year: Calendar.current.component(.year, from: Date()),
        theme: ThemeManager.shared.themes.first ?? ThemeManager.shared.theme(for: "minimal-light"),
        showTodayLine: true,
        eventFontSize: AppSettings.eventFontSizeDefault
    )
    .frame(width: 1100, height: 700)
}
