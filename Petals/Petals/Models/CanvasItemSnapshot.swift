import Foundation

/// CanvasItem과 VisionBoardItem의 콘텐츠 프로퍼티를 통합하는 프로토콜
protocol CanvasContentProperties: AnyObject {
    var imageFileName: String? { get set }
    var thumbnailData: Data? { get set }
    var text: String? { get set }
    var fontSize: Double? { get set }
    var fontName: String? { get set }
    var textColor: String? { get set }
    var textAlignment: String? { get set }
    var isBold: Bool? { get set }
    var isItalic: Bool? { get set }
    var stickerName: String? { get set }
    var shapeType: String? { get set }
    var fillColor: String? { get set }
    var strokeColor: String? { get set }
    var strokeWidth: Double? { get set }
    var cornerRadius: Double? { get set }
}

extension CanvasItem: CanvasContentProperties {}
extension VisionBoardItem: CanvasContentProperties {}

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
    let cornerRadius: Double?

    // 비전보드 절대 크기 (크로스 모드 붙여넣기용)
    let absoluteWidth: Double?
    let absoluteHeight: Double?

    init(from item: CanvasItem, containerSize: CGSize) {
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
        self.cornerRadius = item.cornerRadius
        self.absoluteWidth = item.relativeWidth * containerSize.width
        self.absoluteHeight = item.relativeHeight * containerSize.height
    }

    init(from item: VisionBoardItem) {
        self.type = item.type
        self.relativeX = 0.5
        self.relativeY = 0.5
        self.relativeWidth = 0.1
        self.relativeHeight = 0.1
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
        self.cornerRadius = item.cornerRadius
        self.absoluteWidth = item.width
        self.absoluteHeight = item.height
    }

    /// 스냅샷의 콘텐츠 프로퍼티를 대상 아이템에 적용
    func applyContent(to item: some CanvasContentProperties) {
        item.imageFileName = imageFileName
        item.thumbnailData = thumbnailData
        item.text = text
        item.fontSize = fontSize
        item.fontName = fontName
        item.textColor = textColor
        item.textAlignment = textAlignment
        item.isBold = isBold
        item.isItalic = isItalic
        item.stickerName = stickerName
        item.shapeType = shapeType
        item.fillColor = fillColor
        item.strokeColor = strokeColor
        item.strokeWidth = strokeWidth
        item.cornerRadius = cornerRadius
    }
}
