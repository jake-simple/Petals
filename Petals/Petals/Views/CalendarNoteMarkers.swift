import SwiftUI

struct CalendarNoteMarkers: View {
    let year: Int
    let startMonth: Int
    let monthsShown: Int
    let notes: [CalendarNote]
    let theme: Theme
    let focusedDateKey: Int?
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
                        path.move(to: CGPoint(x: 5, y: 0))
                        path.addLine(to: CGPoint(x: 10, y: 0))
                        path.addLine(to: CGPoint(x: 10, y: 5))
                        path.closeSubpath()
                    }
                    .fill(theme.eventTextColor.opacity(0.7))
                    .frame(width: 10, height: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: rect.maxX - 5, y: rect.minY + 5)
                .accessibilityLabel("Show notes")
                .help("Show notes")
            }
            if let key = focusedDateKey, key / 10000 == year {
                let month = key / 100 % 100
                let day = key % 100
                if month >= startMonth && month < startMonth + monthsShown {
                    let rect = layout.fullCellRect(month: month, day: day)
                    Rectangle().stroke(theme.eventTextColor.opacity(0.7), lineWidth: 2)
                        .frame(width: rect.width - 2, height: rect.height - 2)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
