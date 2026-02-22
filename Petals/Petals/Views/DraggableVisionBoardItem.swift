import AppKit
import SwiftUI
import SwiftData

struct DraggableVisionBoardItem: View, Equatable {
    static func == (lhs: DraggableVisionBoardItem, rhs: DraggableVisionBoardItem) -> Bool {
        lhs.item.persistentModelID == rhs.item.persistentModelID
        && lhs.scale == rhs.scale
        && lhs.isSelected == rhs.isSelected
        && lhs.multipleSelected == rhs.multipleSelected
        && lhs.multiDragOffset == rhs.multiDragOffset
    }

    @Bindable var item: VisionBoardItem
    let scale: CGFloat
    let isSelected: Bool
    let multipleSelected: Bool
    var multiDragOffset: CGSize = .zero
    let onSelect: (_ addToSelection: Bool) -> Void
    @Binding var showInspector: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    var onMoveAll: ((_ translation: CGSize) -> Void)?
    var onMoveAllEnd: ((_ translation: CGSize) -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero
    @State private var activeHandle: HandlePos?
    @State private var initialBounds: (x: Double, y: Double, w: Double, h: Double) = (0, 0, 0, 0)
    @State private var isEditing = false
    @State private var wasConstrained = false

    // 절대좌표 기반 크기 계산
    private var w: CGFloat {
        if activeHandle != nil {
            return max(20, item.width + resizeDeltaW)
        }
        return max(20, item.width)
    }

    private var h: CGFloat {
        if activeHandle == nil, let ar = item.aspectRatio, ar > 0 {
            return max(20, w / ar)
        }
        if activeHandle != nil {
            return max(20, item.height + resizeDeltaH)
        }
        return max(20, item.height)
    }

    // 캔버스 공간에서의 중심점
    private var cx: CGFloat {
        let baseX = item.x + (activeHandle != nil ? resizeDeltaX : 0) + dragOffset.width
        return baseX + w / 2 + multiDragOffset.width
    }

    private var cy: CGFloat {
        let baseY = item.y + (activeHandle != nil ? resizeDeltaY : 0) + dragOffset.height
        return baseY + h / 2 + multiDragOffset.height
    }

    private var imageCornerRadius: CGFloat {
        let pct = item.cornerRadius ?? 0
        return min(w, h) / 2 * pct / 100
    }

    var body: some View {
        ZStack {
            VisionBoardItemView(item: item, isEditing: $isEditing)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius))
                .contentShape(Rectangle())
                .rotationEffect(.degrees(item.rotation))
                .opacity(item.opacity)
                .popover(isPresented: Binding(
                    get: { isSelected && showInspector && !multipleSelected },
                    set: { if !$0 { showInspector = false } }
                )) {
                    VisionBoardInspectorPanel(item: item) {
                        onDelete()
                        showInspector = false
                    }
                }
                .onTapGesture(count: 2) {
                    if CanvasItemType(rawValue: item.type) == .text {
                        isEditing = true
                    }
                }
                .position(x: cx, y: cy)
                .gesture(moveGesture)
                .contextMenu {
                    Button("복사하기") { onCopy() }
                    if !multipleSelected {
                        Button("붙여넣기") { onPaste() }
                        Divider()
                        Button("Edit") { onSelect(false); showInspector = true }
                    }
                    Divider()
                    Button("Bring to Front") { onBringToFront() }
                    Button("Send to Back") { onSendToBack() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                }
                .onChange(of: isSelected) { _, selected in
                    if !selected { isEditing = false }
                }

            if isSelected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
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
                if NSEvent.modifierFlags.contains(.command) {
                    dragOffset = .zero
                    return
                }
                if multipleSelected, let onMoveAll {
                    onMoveAll(value.translation)
                } else {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                guard !isEditing else { return }
                dragOffset = .zero
                if NSEvent.modifierFlags.contains(.command) { return }
                if multipleSelected, let onMoveAllEnd {
                    onMoveAllEnd(value.translation)
                } else {
                    item.x += value.translation.width
                    item.y += value.translation.height
                }
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
                    initialBounds = (item.x, item.y, item.width, item.height)
                    wasConstrained = false
                }
                if NSEvent.modifierFlags.contains(.command) {
                    wasConstrained = true
                }
                resizeOffset = value.translation
            }
            .onEnded { _ in
                let constrained = wasConstrained || NSEvent.modifierFlags.contains(.command)
                item.x = initialBounds.x + resizeDeltaX
                item.y = initialBounds.y + resizeDeltaY
                item.width = max(20, initialBounds.w + resizeDeltaW)
                item.height = max(20, initialBounds.h + resizeDeltaH)
                // Cmd 누른 상태에서 끝났을 때만 비율 잠금, 아니면 해제
                item.aspectRatio = constrained ? item.width / item.height : nil
                activeHandle = nil
                resizeOffset = .zero
                wasConstrained = false
            }
    }

    // MARK: - Resize deltas (절대좌표)

    private var effectiveResizeOffset: CGSize {
        guard wasConstrained || NSEvent.modifierFlags.contains(.command), let pos = activeHandle else {
            return resizeOffset
        }

        let dx = resizeOffset.width
        let dy = resizeOffset.height

        let wSign: CGFloat = (pos == .topLeft || pos == .bottomLeft) ? -1 : 1
        let hSign: CGFloat = (pos == .topLeft || pos == .topRight) ? -1 : 1

        let newW = initialBounds.w + wSign * dx
        let newH = initialBounds.h + hSign * dy

        let side: CGFloat
        if abs(newW - initialBounds.w) >= abs(newH - initialBounds.h) {
            side = max(20, newW)
        } else {
            side = max(20, newH)
        }

        let adjustedDx = wSign * (side - initialBounds.w)
        let adjustedDy = hSign * (side - initialBounds.h)

        return CGSize(width: adjustedDx, height: adjustedDy)
    }

    private var resizeDeltaX: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dx = effectiveResizeOffset.width
        switch pos {
        case .topLeft, .bottomLeft: return dx
        default: return 0
        }
    }

    private var resizeDeltaY: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dy = effectiveResizeOffset.height
        switch pos {
        case .topLeft, .topRight: return dy
        default: return 0
        }
    }

    private var resizeDeltaW: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dx = effectiveResizeOffset.width
        switch pos {
        case .topLeft, .bottomLeft: return -dx
        case .topRight, .bottomRight: return dx
        }
    }

    private var resizeDeltaH: CGFloat {
        guard let pos = activeHandle else { return 0 }
        let dy = effectiveResizeOffset.height
        switch pos {
        case .topLeft, .topRight: return -dy
        case .bottomLeft, .bottomRight: return dy
        }
    }
}

// MARK: - Vision Board Inspector Panel

struct VisionBoardInspectorPanel: View {
    @Bindable var item: VisionBoardItem
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section("Transform") {
                LabeledContent("Opacity") {
                    Slider(value: steppedBinding($item.opacity, step: 0.05), in: 0.1...1.0)
                }
                LabeledContent("Rotation") {
                    HStack {
                        Slider(value: steppedBinding($item.rotation, step: 1), in: -180...180)
                        Text("\(Int(item.rotation))\u{00B0}")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }

            switch CanvasItemType(rawValue: item.type) {
            case .image: imageSection
            case .text: textSection
            case .shape: shapeSection
            case .sticker: stickerSection
            default: EmptyView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 260)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var imageSection: some View {
        Section("Image") {
            LabeledContent("Corner Radius") {
                Slider(value: Binding(
                    get: { item.cornerRadius ?? 0 },
                    set: { item.cornerRadius = $0 }
                ), in: 0...100)
            }
        }
    }

    @ViewBuilder
    private var textSection: some View {
        Section("Text") {
            TextField("Content", text: Binding(
                get: { item.text ?? "" },
                set: { item.text = $0 }
            ), axis: .vertical)

            Picker("Font", selection: Binding(
                get: { item.fontName ?? "" },
                set: { item.fontName = $0.isEmpty ? nil : $0 }
            )) {
                Text("System Default").tag("")
                ForEach(Self.availableFonts, id: \.self) { name in
                    Text(name).font(.custom(name, size: 13)).tag(name)
                }
            }

            LabeledContent("Size") {
                HStack {
                    Slider(value: Binding(
                        get: { item.fontSize ?? 32 },
                        set: { item.fontSize = $0 }
                    ), in: 6...200)
                    Text("\(Int(item.fontSize ?? 32))pt")
                        .monospacedDigit()
                        .frame(width: 44)
                }
            }

            HStack {
                Toggle(isOn: Binding(
                    get: { item.isBold ?? false },
                    set: { item.isBold = $0 }
                )) {
                    Image(systemName: "bold")
                }
                .toggleStyle(.button)

                Toggle(isOn: Binding(
                    get: { item.isItalic ?? false },
                    set: { item.isItalic = $0 }
                )) {
                    Image(systemName: "italic")
                }
                .toggleStyle(.button)
            }

            Picker("Alignment", selection: Binding(
                get: { item.textAlignment ?? "leading" },
                set: { item.textAlignment = $0 }
            )) {
                Text("Left").tag("leading")
                Text("Center").tag("center")
                Text("Right").tag("trailing")
            }
            .pickerStyle(.segmented)

            ColorPicker("Color", selection: hexColorBinding(\.textColor, default: "#333333"))
        }
    }

    private static let availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    @ViewBuilder
    private var shapeSection: some View {
        Section("Shape") {
            Picker("Type", selection: Binding(
                get: { item.shapeType ?? "rectangle" },
                set: { item.shapeType = $0 }
            )) {
                Text("Rectangle").tag("rectangle")
                Text("Circle").tag("circle")
                Text("Line").tag("line")
            }

            ColorPicker("Fill", selection: hexColorBinding(\.fillColor, default: "#4A90D9"))
            ColorPicker("Stroke", selection: hexColorBinding(\.strokeColor, default: "#2C5F8A"))

            LabeledContent("Stroke Width") {
                Slider(value: Binding(
                    get: { item.strokeWidth ?? 1 },
                    set: { item.strokeWidth = $0 }
                ), in: 0...10)
            }
        }
    }

    @ViewBuilder
    private var stickerSection: some View {
        Section("Sticker") {
            ColorPicker("Color", selection: hexColorBinding(\.fillColor, default: "#000000"))
        }
    }

    private func steppedBinding(_ binding: Binding<Double>, step: Double) -> Binding<Double> {
        Binding {
            binding.wrappedValue
        } set: { newValue in
            binding.wrappedValue = (newValue / step).rounded() * step
        }
    }

    private func hexColorBinding(_ keyPath: ReferenceWritableKeyPath<VisionBoardItem, String?>,
                                  default defaultHex: String) -> Binding<Color> {
        Binding {
            Color(hex: item[keyPath: keyPath] ?? defaultHex)
        } set: { newColor in
            item[keyPath: keyPath] = newColor.toHex()
        }
    }
}
