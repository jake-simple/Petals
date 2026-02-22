import SwiftUI

struct VisionBoardItemView: View {
    @Bindable var item: VisionBoardItem
    @Binding var isEditing: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        switch CanvasItemType(rawValue: item.type) {
        case .image: imageContent
        case .text: textContent
        case .sticker: stickerContent
        case .shape: shapeContent
        case .none: Color.clear
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageContent: some View {
        if let fileName = item.imageFileName, let image = ImageManager.loadImage(fileName: fileName) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
        } else if let data = item.thumbnailData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(.gray.opacity(0.2))
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
    }

    // MARK: - Text (절대 fontSize 사용)

    @ViewBuilder
    private var textContent: some View {
        if isEditing {
            TextField("", text: Binding(
                get: { item.text ?? "" },
                set: { item.text = $0 }
            ), axis: .vertical)
            .font(textFont())
            .foregroundStyle(item.textColor.map { Color(hex: $0) } ?? .primary)
            .textFieldStyle(.plain)
            .multilineTextAlignment(textAlign)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlign)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused { isEditing = false }
            }
        } else {
            Text(item.text ?? String(localized: "Text"))
                .font(textFont())
                .foregroundStyle(item.textColor.map { Color(hex: $0) } ?? .primary)
                .multilineTextAlignment(textAlign)
                .minimumScaleFactor(0.1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlign)
        }
    }

    private func textFont() -> Font {
        let size = max(6, item.fontSize ?? 32)
        let bold = item.isBold ?? false
        let italic = item.isItalic ?? false

        if let fontName = item.fontName {
            // 커스텀 폰트 패밀리 → NSFont로 trait 적용
            var traits: NSFontTraitMask = []
            if bold { traits.insert(.boldFontMask) }
            if italic { traits.insert(.italicFontMask) }
            if let nsFont = NSFontManager.shared.font(
                withFamily: fontName, traits: traits, weight: 5, size: size
            ) {
                return Font(nsFont)
            }
            return .custom(fontName, size: size)
        }

        var font: Font = .system(size: size, weight: bold ? .bold : .regular)
        if italic { font = font.italic() }
        return font
    }

    private var textAlign: TextAlignment {
        switch item.textAlignment {
        case "center": .center
        case "trailing": .trailing
        default: .leading
        }
    }

    private var frameAlign: Alignment {
        switch item.textAlignment {
        case "center": .center
        case "trailing": .trailing
        default: .leading
        }
    }

    // MARK: - Sticker

    @ViewBuilder
    private var stickerContent: some View {
        if let name = item.stickerName {
            if name.unicodeScalars.allSatisfy({ $0.properties.isEmoji && !$0.isASCII }) {
                Text(name).font(.system(size: item.fontSize ?? 40))
            } else {
                Image(systemName: name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(item.fillColor.map { Color(hex: $0) } ?? .primary)
            }
        }
    }

    // MARK: - Shape

    @ViewBuilder
    private var shapeContent: some View {
        let fill = item.fillColor.map { Color(hex: $0) } ?? .clear
        let stroke = item.strokeColor.map { Color(hex: $0) } ?? .primary
        let lw = item.strokeWidth ?? 1

        switch item.shapeType {
        case "circle":
            Circle().fill(fill).overlay { Circle().stroke(stroke, lineWidth: lw) }
        case "line":
            GeometryReader { proxy in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }.stroke(stroke, lineWidth: lw)
            }
        default:
            Rectangle().fill(fill).overlay { Rectangle().stroke(stroke, lineWidth: lw) }
        }
    }
}
