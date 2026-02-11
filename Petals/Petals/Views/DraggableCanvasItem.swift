import SwiftUI
import SwiftData

struct DraggableCanvasItem: View {
    @Bindable var item: CanvasItem
    let containerSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero
    @State private var activeHandle: HandlePos?
    @State private var initialBounds: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)

    private var w: CGFloat { max(10, (item.relativeWidth + (activeHandle != nil ? resizeDeltaW : 0)) * containerSize.width) }
    private var h: CGFloat { max(10, (item.relativeHeight + (activeHandle != nil ? resizeDeltaH : 0)) * containerSize.height) }
    private var cx: CGFloat {
        let baseX = item.relativeX + (activeHandle != nil ? resizeDeltaX : 0) + dragOffset.width / containerSize.width
        return baseX * containerSize.width + w / 2
    }
    private var cy: CGFloat {
        let baseY = item.relativeY + (activeHandle != nil ? resizeDeltaY : 0) + dragOffset.height / containerSize.height
        return baseY * containerSize.height + h / 2
    }

    var body: some View {
        ZStack {
            CanvasItemView(item: item)
                .frame(width: w, height: h)
                .rotationEffect(.degrees(item.rotation))
                .opacity(item.opacity)
                .position(x: cx, y: cy)
                .onTapGesture { onSelect() }
                .gesture(moveGesture)
                .contextMenu {
                    Button("Bring to Front") { onBringToFront() }
                    Button("Send to Back") { onSendToBack() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                }

            if isSelected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1)
                    .frame(width: w, height: h)
                    .position(x: cx, y: cy)

                ForEach(HandlePos.allCases, id: \.self) { pos in
                    handleView(pos)
                }
            }
        }
    }

    // MARK: - Move

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                item.relativeX += value.translation.width / containerSize.width
                item.relativeY += value.translation.height / containerSize.height
                dragOffset = .zero
            }
    }

    // MARK: - Handles

    @ViewBuilder
    private func handleView(_ pos: HandlePos) -> some View {
        let pt = handlePoint(pos)
        Circle()
            .fill(.white)
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 8, height: 8)
            .position(x: pt.x, y: pt.y)
            .gesture(resizeGesture(pos))
    }

    private func handlePoint(_ pos: HandlePos) -> CGPoint {
        let left = cx - w / 2
        let right = cx + w / 2
        let top = cy - h / 2
        let bottom = cy + h / 2
        switch pos {
        case .topLeft: return CGPoint(x: left, y: top)
        case .topRight: return CGPoint(x: right, y: top)
        case .bottomLeft: return CGPoint(x: left, y: bottom)
        case .bottomRight: return CGPoint(x: right, y: bottom)
        }
    }

    private func resizeGesture(_ pos: HandlePos) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = pos
                    initialBounds = (item.relativeX, item.relativeY, item.relativeWidth, item.relativeHeight)
                }
                resizeOffset = value.translation
            }
            .onEnded { _ in
                item.relativeX = initialBounds.x + resizeDeltaX
                item.relativeY = initialBounds.y + resizeDeltaY
                item.relativeWidth = max(0.02, initialBounds.w + resizeDeltaW)
                item.relativeHeight = max(0.02, initialBounds.h + resizeDeltaH)
                activeHandle = nil
                resizeOffset = .zero
            }
    }

    // MARK: - Resize deltas

    private var resizeDeltaX: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dx = resizeOffset.width / containerSize.width
        switch pos {
        case .topLeft, .bottomLeft: return dx
        default: return 0
        }
    }

    private var resizeDeltaY: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dy = resizeOffset.height / containerSize.height
        switch pos {
        case .topLeft, .topRight: return dy
        default: return 0
        }
    }

    private var resizeDeltaW: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dx = resizeOffset.width / containerSize.width
        switch pos {
        case .topLeft, .bottomLeft: return -dx
        case .topRight, .bottomRight: return dx
        }
    }

    private var resizeDeltaH: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dy = resizeOffset.height / containerSize.height
        switch pos {
        case .topLeft, .topRight: return -dy
        case .bottomLeft, .bottomRight: return dy
        }
    }
}

enum HandlePos: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}
