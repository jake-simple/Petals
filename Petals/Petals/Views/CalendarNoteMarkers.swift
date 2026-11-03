import SwiftUI

struct CalendarNoteMarkers: View {
    let year: Int
    let startMonth: Int
    let monthsShown: Int
    let notes: [CalendarNote]
    let theme: Theme
    let onSelect: (Int, Int) -> Void

    private var markedDates: [Int] {
        Array(Set(notes.filter { $0.year == year && $0.month >= startMonth && $0.month < startMonth + monthsShown }.map(\.dateKey))).sorted()
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = CalendarLayout(size: proxy.size, monthsShown: monthsShown, startMonth: startMonth, year: year)
            ForEach(markedDates, id: \.self) { key in
                let month = key / 100 % 100
                let day = key % 100
                let rect = layout.fullCellRect(month: month, day: day)
                Button { onSelect(month, day) } label: {
                    Path { path in
                        path.move(to: CGPoint(x: 14, y: 6))
                        path.addLine(to: CGPoint(x: 14, y: 14))
                        path.addLine(to: CGPoint(x: 6, y: 14))
                        path.closeSubpath()
                    }
                    .fill(theme.eventTextColor.opacity(0.7))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: rect.maxX - 7, y: rect.maxY - 7)
                .accessibilityLabel("Show notes")
                .help("Show notes")
            }
        }
    }
}
