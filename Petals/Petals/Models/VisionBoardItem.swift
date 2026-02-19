import Foundation
import SwiftData

@Model
final class VisionBoardItem {
    // 공통 (CloudKit 호환: 모든 non-optional에 기본값)
    var type: String = "text"
    var x: Double = 0
    var y: Double = 0
    var width: Double = 200
    var height: Double = 200
    var rotation: Double = 0
    var zIndex: Int = 0
    var opacity: Double = 1.0
    var aspectRatio: Double?
    var createdAt: Date = Date()

    // 이미지
    var imageFileName: String?
    var thumbnailData: Data?
    var cornerRadius: Double?

    // 텍스트
    var text: String?
    var fontSize: Double?
    var fontName: String?
    var textColor: String?
    var textAlignment: String?
    var isBold: Bool?
    var isItalic: Bool?

    // 스티커
    var stickerName: String?

    // 도형
    var shapeType: String?
    var fillColor: String?
    var strokeColor: String?
    var strokeWidth: Double?

    init(type: CanvasItemType,
         x: Double = 0,
         y: Double = 0,
         width: Double = 200,
         height: Double = 200,
         rotation: Double = 0,
         zIndex: Int = 0,
         opacity: Double = 1.0) {
        self.type = type.rawValue
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zIndex = zIndex
        self.opacity = opacity
        self.createdAt = Date()
    }

    // MARK: - Factory methods

    /// 캔버스 공간의 중심점을 받아 이미지 아이템 생성
    static func newImage(at center: CGPoint, fileName: String, thumbnail: Data, zIndex: Int) -> VisionBoardItem {
        let w: Double = 300
        let h: Double = 300
        let item = VisionBoardItem(type: .image, x: center.x - w / 2, y: center.y - h / 2,
                                   width: w, height: h, zIndex: zIndex)
        item.imageFileName = fileName
        item.thumbnailData = thumbnail
        return item
    }

    static func newText(at center: CGPoint, zIndex: Int) -> VisionBoardItem {
        let w: Double = 200
        let h: Double = 60
        let item = VisionBoardItem(type: .text, x: center.x - w / 2, y: center.y - h / 2,
                                   width: w, height: h, zIndex: zIndex)
        item.text = String(localized: "New Text")
        item.fontSize = 32
        item.textColor = "#333333"
        return item
    }

    static func newShape(at center: CGPoint, _ shapeType: String, zIndex: Int) -> VisionBoardItem {
        let s: Double = 150
        let item = VisionBoardItem(type: .shape, x: center.x - s / 2, y: center.y - s / 2,
                                   width: s, height: s, zIndex: zIndex)
        item.shapeType = shapeType
        item.fillColor = "#4A90D9"
        item.strokeColor = "#2C5F8A"
        item.strokeWidth = 2
        return item
    }

    static func newSticker(at center: CGPoint, _ name: String, zIndex: Int) -> VisionBoardItem {
        let s: Double = 80
        let item = VisionBoardItem(type: .sticker, x: center.x - s / 2, y: center.y - s / 2,
                                   width: s, height: s, zIndex: zIndex)
        item.stickerName = name
        item.fontSize = 40
        return item
    }
}
