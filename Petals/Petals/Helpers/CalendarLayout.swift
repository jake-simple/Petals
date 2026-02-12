import Foundation

struct CalendarLayout: Sendable {
    let size: CGSize
    let monthLabelWidth: CGFloat = 48
    let perMonthLabelHeight: CGFloat = 18

    let monthsShown: Int
    let startMonth: Int

    var daysPerRow: Int {
        switch monthsShown {
        case 6: return 16
        case 1, 3: return 8
        default: return 31
        }
    }

    var rowsPerMonth: Int {
        switch monthsShown {
        case 6: return 2
        case 1, 3: return 4
        default: return 1
        }
    }

    var totalRows: Int { monthsShown * rowsPerMonth }

    var gridWidth: CGFloat { size.width - monthLabelWidth }
    var rowHeight: CGFloat { size.height / CGFloat(totalRows) }
    var cellWidth: CGFloat { gridWidth / CGFloat(daysPerRow) }
    /// Height of the event area within each visual row (below day labels).
    var cellHeight: CGFloat { rowHeight - perMonthLabelHeight }

    init(size: CGSize, monthsShown: Int = 12, startMonth: Int = 1) {
        self.size = size
        self.monthsShown = monthsShown
        self.startMonth = startMonth
    }

    /// Top-left of the event area for a given month/day cell.
    func cellOrigin(month: Int, day: Int) -> CGPoint {
        let monthOffset = month - startMonth
        let subrow = (day - 1) / daysPerRow
        let col = (day - 1) % daysPerRow
        let visualRow = monthOffset * rowsPerMonth + subrow
        return CGPoint(
            x: monthLabelWidth + CGFloat(col) * cellWidth,
            y: CGFloat(visualRow) * rowHeight + perMonthLabelHeight
        )
    }

    /// Top-left of the entire visual row (including day label area).
    func rowOrigin(month: Int) -> CGPoint {
        let monthOffset = month - startMonth
        let visualRow = monthOffset * rowsPerMonth
        return CGPoint(
            x: monthLabelWidth,
            y: CGFloat(visualRow) * rowHeight
        )
    }

    func cellAt(_ point: CGPoint) -> (month: Int, day: Int)? {
        let visualRow = Int(point.y / rowHeight)
        let col = Int((point.x - monthLabelWidth) / cellWidth)
        guard visualRow >= 0, visualRow < totalRows,
              col >= 0, col < daysPerRow else { return nil }

        let monthOffset = visualRow / rowsPerMonth
        let subrow = visualRow % rowsPerMonth
        let month = startMonth + monthOffset
        let day = subrow * daysPerRow + col + 1
        guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        return (month: month, day: day)
    }
}
