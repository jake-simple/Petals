import Foundation
import CoreGraphics

struct CalendarLayout: Sendable {
    let size: CGSize
    let monthLabelWidth: CGFloat = 48
    let perMonthLabelHeight: CGFloat = 18
    /// 셀 우측 가장자리에서 날짜 숫자까지의 여백.
    static let dayLabelInset: CGFloat = 5

    let monthsShown: Int
    let startMonth: Int
    let year: Int

    /// 분기(3)/월(1) 보기는 일반 캘린더처럼 요일(일~토) 열에 맞춰 날짜를 배치한다.
    /// 연(12) 보기는 기존처럼 한 달을 한 행에 가로로 펼친다.
    static func usesWeekdayMode(monthsShown: Int) -> Bool { monthsShown == 1 || monthsShown == 3 }
    var weekdayMode: Bool { Self.usesWeekdayMode(monthsShown: monthsShown) }

    /// weekdayMode에서 각 달의 그리드 정보 (가변 주 수).
    struct MonthInfo: Sendable {
        let month: Int
        let firstWeekdayIndex: Int   // 0 = 일요일 ... 6 = 토요일
        let weeks: Int
        let daysInMonth: Int
        let startRow: Int            // 뷰 내 누적 시각적 행 오프셋
    }
    let months: [MonthInfo]

    /// 상단 요일 헤더 높이 (weekdayMode에서만).
    var headerHeight: CGFloat { weekdayMode ? 18 : 0 }

    var daysPerRow: Int { weekdayMode ? 7 : 31 }

    var totalRows: Int {
        weekdayMode ? months.reduce(0) { $0 + $1.weeks } : monthsShown
    }

    var gridWidth: CGFloat { size.width - monthLabelWidth }
    var rowHeight: CGFloat { (size.height - headerHeight) / CGFloat(max(totalRows, 1)) }
    var cellWidth: CGFloat { gridWidth / CGFloat(daysPerRow) }
    /// Height of the event area within each visual row (below day labels).
    var cellHeight: CGFloat { rowHeight - perMonthLabelHeight }

    init(size: CGSize, monthsShown: Int = 12, startMonth: Int = 1, year: Int = 2000) {
        self.size = size
        self.monthsShown = monthsShown
        self.startMonth = startMonth
        self.year = year

        var infos: [MonthInfo] = []
        if Self.usesWeekdayMode(monthsShown: monthsShown) {
            let cal = Calendar.current
            var cumulative = 0
            let endMonth = startMonth + monthsShown - 1
            for m in startMonth...endMonth where m >= 1 && m <= 12 {
                guard let firstDate = cal.date(from: DateComponents(year: year, month: m, day: 1)),
                      let range = cal.range(of: .day, in: .month, for: firstDate) else { continue }
                let daysInMonth = range.count
                let offset = cal.component(.weekday, from: firstDate) - 1   // 일요일 시작
                let weeks = Int(ceil(Double(offset + daysInMonth) / 7.0))
                infos.append(MonthInfo(month: m, firstWeekdayIndex: offset,
                                       weeks: weeks, daysInMonth: daysInMonth, startRow: cumulative))
                cumulative += weeks
            }
        }
        self.months = infos
    }

    /// 해당 달의 일수. weekdayMode에서는 사전계산된 값을, 그 외에는 직접 계산한다.
    func daysInMonth(_ month: Int) -> Int {
        if let info = months.first(where: { $0.month == month }) { return info.daysInMonth }
        let cal = Calendar.current
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    /// (월, 일) → 시각적 (행, 열). 범위를 벗어나면 nil.
    func gridPosition(month: Int, day: Int) -> (row: Int, col: Int)? {
        if weekdayMode {
            guard let info = months.first(where: { $0.month == month }) else { return nil }
            let idx = info.firstWeekdayIndex + (day - 1)
            return (info.startRow + idx / 7, idx % 7)
        } else {
            return (month - startMonth, day - 1)
        }
    }

    /// Top-left of the event area for a given month/day cell.
    func cellOrigin(month: Int, day: Int) -> CGPoint {
        guard let pos = gridPosition(month: month, day: day) else {
            return CGPoint(x: monthLabelWidth, y: headerHeight)
        }
        return CGPoint(
            x: monthLabelWidth + CGFloat(pos.col) * cellWidth,
            y: headerHeight + CGFloat(pos.row) * rowHeight + perMonthLabelHeight
        )
    }

    /// Full cell rect including the day-label strip — used for selection borders and popover anchors.
    func fullCellRect(month: Int, day: Int) -> CGRect {
        let origin = cellOrigin(month: month, day: day)
        return CGRect(x: origin.x, y: origin.y - perMonthLabelHeight,
                      width: cellWidth, height: rowHeight)
    }

    func cellAt(_ point: CGPoint) -> (month: Int, day: Int)? {
        guard point.x >= monthLabelWidth, point.y >= headerHeight else { return nil }
        let col = Int((point.x - monthLabelWidth) / cellWidth)
        let visualRow = Int((point.y - headerHeight) / rowHeight)
        guard col >= 0, col < daysPerRow, visualRow >= 0, visualRow < totalRows else { return nil }

        if weekdayMode {
            guard let info = months.first(where: { visualRow >= $0.startRow && visualRow < $0.startRow + $0.weeks })
            else { return nil }
            let subrow = visualRow - info.startRow
            let day = subrow * 7 + col - info.firstWeekdayIndex + 1
            guard day >= 1, day <= info.daysInMonth else { return nil }
            return (month: info.month, day: day)
        } else {
            let month = startMonth + visualRow
            let day = col + 1
            guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
            return (month: month, day: day)
        }
    }

    /// [startDay, endDay] 범위를 같은 시각적 행에 속하는 연속 구간들로 분할.
    /// 주 경계를 넘는 이벤트가 한 줄짜리 바로 그려지도록 보장한다.
    func rowRuns(month: Int, startDay: Int, endDay: Int) -> [(startDay: Int, endDay: Int)] {
        guard startDay <= endDay else { return [] }
        guard weekdayMode, let info = months.first(where: { $0.month == month }) else {
            return [(startDay, endDay)]
        }
        var runs: [(startDay: Int, endDay: Int)] = []
        var d = startDay
        while d <= endDay {
            let row = (info.firstWeekdayIndex + d - 1) / 7
            let lastDayInRow = (row + 1) * 7 - info.firstWeekdayIndex   // 해당 행의 마지막 날
            let e = min(endDay, lastDayInRow)
            runs.append((d, e))
            d = e + 1
        }
        return runs
    }
}
