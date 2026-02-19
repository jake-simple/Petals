import SwiftUI

struct InfiniteCanvasBackground: View {
    let scale: CGFloat
    let offset: CGSize

    private let baseDotSpacing: CGFloat = 24
    private let dotRadius: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let screenSpacing = baseDotSpacing * scale

            guard screenSpacing > 3 else { return }

            let phaseX = offset.width.truncatingRemainder(dividingBy: screenSpacing)
            let phaseY = offset.height.truncatingRemainder(dividingBy: screenSpacing)

            let startX = phaseX - screenSpacing
            let startY = phaseY - screenSpacing

            let d = dotRadius * 2

            // 모든 도트를 하나의 Path에 합산 → fill 1회
            var dots = Path()
            var x = startX
            while x < size.width + screenSpacing {
                var y = startY
                while y < size.height + screenSpacing {
                    dots.addRect(CGRect(x: x - dotRadius, y: y - dotRadius, width: d, height: d))
                    y += screenSpacing
                }
                x += screenSpacing
            }
            context.fill(dots, with: .color(.gray.opacity(0.25)))
        }
    }
}
