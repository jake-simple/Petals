import Foundation

struct CanvasItemSnapshot {
    let type: String
    let relativeX: Double
    let relativeY: Double
    let relativeWidth: Double
    let relativeHeight: Double
    let rotation: Double
    let opacity: Double
    let imageFileName: String?
    let thumbnailData: Data?
    let text: String?
    let fontSize: Double?
    let fontName: String?
    let textColor: String?
    let textAlignment: String?
    let isBold: Bool?
    let isItalic: Bool?
    let stickerName: String?
    let shapeType: String?
    let fillColor: String?
    let strokeColor: String?
    let strokeWidth: Double?

    init(from item: CanvasItem) {
        self.type = item.type
        self.relativeX = item.relativeX
        self.relativeY = item.relativeY
        self.relativeWidth = item.relativeWidth
        self.relativeHeight = item.relativeHeight
        self.rotation = item.rotation
        self.opacity = item.opacity
        self.imageFileName = item.imageFileName
        self.thumbnailData = item.thumbnailData
        self.text = item.text
        self.fontSize = item.fontSize
        self.fontName = item.fontName
        self.textColor = item.textColor
        self.textAlignment = item.textAlignment
        self.isBold = item.isBold
        self.isItalic = item.isItalic
        self.stickerName = item.stickerName
        self.shapeType = item.shapeType
        self.fillColor = item.fillColor
        self.strokeColor = item.strokeColor
        self.strokeWidth = item.strokeWidth
    }
}
