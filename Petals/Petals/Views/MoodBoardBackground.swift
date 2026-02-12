import SwiftUI

struct MoodBoardBackground: View {
    let gridLineColor: String

    var body: some View {
        Canvas { context, size in
            let dotColor = Color(hex: gridLineColor).opacity(0.4)
            let spacing: CGFloat = 20
            let radius: CGFloat = 1.5

            var x: CGFloat = spacing
            while x < size.width {
                var y: CGFloat = spacing
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x - radius, y: y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .color(dotColor)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
    }
}
