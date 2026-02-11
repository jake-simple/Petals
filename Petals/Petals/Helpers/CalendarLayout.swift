import Foundation

struct CalendarLayout: Sendable {
    let size: CGSize
    let monthLabelWidth: CGFloat = 48
    let perMonthLabelHeight: CGFloat = 18

    var gridWidth: CGFloat { size.width - monthLabelWidth }
    var rowHeight: CGFloat { size.height / 12 }
    var cellWidth: CGFloat { gridWidth / 31 }
    /// Height of the event area within each month row (below day labels).
    var cellHeight: CGFloat { rowHeight - perMonthLabelHeight }

    /// Top-left of the event area for a given month/day cell.
    func cellOrigin(month: Int, day: Int) -> CGPoint {
        CGPoint(
            x: monthLabelWidth + CGFloat(day - 1) * cellWidth,
            y: CGFloat(month - 1) * rowHeight + perMonthLabelHeight
        )
    }

    /// Top-left of the entire month row (including day label area).
    func rowOrigin(month: Int) -> CGPoint {
        CGPoint(
            x: monthLabelWidth,
            y: CGFloat(month - 1) * rowHeight
        )
    }

    func cellAt(_ point: CGPoint) -> (month: Int, day: Int)? {
        let row = Int(point.y / rowHeight) + 1
        let col = Int((point.x - monthLabelWidth) / cellWidth) + 1
        guard col >= 1, col <= 31, row >= 1, row <= 12 else { return nil }
        return (month: row, day: col)
    }
}
