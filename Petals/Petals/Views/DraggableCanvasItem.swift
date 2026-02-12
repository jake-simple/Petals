import AppKit
import SwiftUI
import SwiftData

struct DraggableCanvasItem: View {
    @Bindable var item: CanvasItem
    let containerSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    @Binding var showInspector: Bool
    let onDelete: () -> Void
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero
    @State private var activeHandle: HandlePos?
    @State private var initialBounds: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)
    @State private var isEditing = false
    @State private var wasConstrained = false

    private var w: CGFloat { max(10, (item.relativeWidth + (activeHandle != nil ? resizeDeltaW : 0)) * containerSize.width) }
    private var h: CGFloat {
        if activeHandle == nil, let ar = item.aspectRatio, ar > 0 {
            return max(10, w / ar)
        }
        return max(10, (item.relativeHeight + (activeHandle != nil ? resizeDeltaH : 0)) * containerSize.height)
    }
    private var cx: CGFloat {
        let baseX = item.relativeX + (activeHandle != nil ? resizeDeltaX : 0) + dragOffset.width / containerSize.width
        return baseX * containerSize.width + w / 2
    }
    private var cy: CGFloat {
        let baseY = item.relativeY + (activeHandle != nil ? resizeDeltaY : 0) + dragOffset.height / containerSize.height
        return baseY * containerSize.height + h / 2
    }

    private var imageCornerRadius: CGFloat {
        let pct = item.cornerRadius ?? 0
        return min(w, h) / 2 * pct / 100
    }

    var body: some View {
        ZStack {
            CanvasItemView(item: item, isEditing: $isEditing)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius))
                .contentShape(Rectangle())
                .rotationEffect(.degrees(item.rotation))
                .opacity(item.opacity)
                .popover(isPresented: Binding(
                    get: { isSelected && showInspector },
                    set: { if !$0 { showInspector = false } }
                )) {
                    InspectorPanel(item: item) {
                        onDelete()
                        showInspector = false
                    }
                }
                .position(x: cx, y: cy)
                .onTapGesture(count: 2) {
                    if CanvasItemType(rawValue: item.type) == .text {
                        isEditing = true
                        onSelect()
                    }
                }
                .onTapGesture { onSelect() }
                .gesture(moveGesture)
                .onChange(of: isSelected) { _, selected in
                    if !selected { isEditing = false }
                }
                .contextMenu {
                    Button("Edit") { onSelect(); showInspector = true }
                    Divider()
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
                guard !isEditing else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isEditing else { return }
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
            .pointerStyle(.frameResize(position: frameResizePosition(for: pos)))
            .position(x: pt.x, y: pt.y)
            .gesture(resizeGesture(pos))
    }

    private func frameResizePosition(for pos: HandlePos) -> FrameResizePosition {
        switch pos {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
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
                    wasConstrained = false
                }
                if NSEvent.modifierFlags.contains(.command) {
                    wasConstrained = true
                }
                resizeOffset = value.translation
            }
            .onEnded { _ in
                item.relativeX = initialBounds.x + resizeDeltaX
                item.relativeY = initialBounds.y + resizeDeltaY
                item.relativeWidth = max(0.02, initialBounds.w + resizeDeltaW)
                item.relativeHeight = max(0.02, initialBounds.h + resizeDeltaH)
                if wasConstrained {
                    let pixelW = item.relativeWidth * containerSize.width
                    let pixelH = item.relativeHeight * containerSize.height
                    item.aspectRatio = pixelW / pixelH
                } else {
                    item.aspectRatio = nil
                }
                activeHandle = nil
                resizeOffset = .zero
            }
    }

    // MARK: - Resize deltas

    /// CMD 키가 눌려 있으면 결과가 정사각형이 되도록 조정된 resize offset 반환
    private var effectiveResizeOffset: CGSize {
        guard wasConstrained || NSEvent.modifierFlags.contains(.command), let pos = activeHandle else {
            return resizeOffset
        }

        let dx = resizeOffset.width
        let dy = resizeOffset.height

        // 핸들에 따른 사이즈 변화 방향 (양수 = 커짐)
        let wSign: CGFloat = (pos == .topLeft || pos == .bottomLeft) ? -1 : 1
        let hSign: CGFloat = (pos == .topLeft || pos == .topRight) ? -1 : 1

        let initialPixelW = initialBounds.w * containerSize.width
        let initialPixelH = initialBounds.h * containerSize.height

        let newPixelW = initialPixelW + wSign * dx
        let newPixelH = initialPixelH + hSign * dy

        // 변화량이 큰 축 기준으로 정사각형 사이즈 결정
        let side: CGFloat
        if abs(newPixelW - initialPixelW) >= abs(newPixelH - initialPixelH) {
            side = max(10, newPixelW)
        } else {
            side = max(10, newPixelH)
        }

        let adjustedDx = wSign * (side - initialPixelW)
        let adjustedDy = hSign * (side - initialPixelH)

        return CGSize(width: adjustedDx, height: adjustedDy)
    }

    private var resizeDeltaX: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dx = effectiveResizeOffset.width / containerSize.width
        switch pos {
        case .topLeft, .bottomLeft: return dx
        default: return 0
        }
    }

    private var resizeDeltaY: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dy = effectiveResizeOffset.height / containerSize.height
        switch pos {
        case .topLeft, .topRight: return dy
        default: return 0
        }
    }

    private var resizeDeltaW: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dx = effectiveResizeOffset.width / containerSize.width
        switch pos {
        case .topLeft, .bottomLeft: return -dx
        case .topRight, .bottomRight: return dx
        }
    }

    private var resizeDeltaH: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dy = effectiveResizeOffset.height / containerSize.height
        switch pos {
        case .topLeft, .topRight: return -dy
        case .bottomLeft, .bottomRight: return dy
        }
    }
}

enum HandlePos: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}
