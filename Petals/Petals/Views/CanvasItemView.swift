import SwiftUI

struct CanvasItemView: View {
    let item: CanvasItem

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

    // MARK: - Text

    @ViewBuilder
    private var textContent: some View {
        Text(item.text ?? "Text")
            .font(.system(
                size: item.fontSize ?? 16,
                weight: (item.isBold ?? false) ? .bold : .regular
            ))
            .italic(item.isItalic ?? false)
            .foregroundStyle(item.textColor.map { Color(hex: $0) } ?? .primary)
            .multilineTextAlignment(textAlign)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlign)
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
