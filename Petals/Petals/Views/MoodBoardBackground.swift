import SwiftUI

struct MoodBoardBackground: View {
    let gridLineColor: String

    var body: some View {
        Canvas { context, size in
            let dotColor = Color(hex: gridLineColor).opacity(0.4)
            let spacing: CGFloat = 20
            let radius: CGFloat = 1.5
            let diameter = radius * 2

            var path = Path()
            var x: CGFloat = spacing
            while x < size.width {
                var y: CGFloat = spacing
                while y < size.height {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: diameter, height: diameter))
                    y += spacing
                }
                x += spacing
            }
            context.fill(path, with: .color(dotColor))
        }
    }
}
