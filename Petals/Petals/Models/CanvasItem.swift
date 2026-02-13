import Foundation
import SwiftData

@Model
final class CanvasItem {
    // 공통 (CloudKit 호환: 모든 non-optional에 기본값)
    var type: String = "text"
    var relativeX: Double = 0
    var relativeY: Double = 0
    var relativeWidth: Double = 0.1
    var relativeHeight: Double = 0.1
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

    /// monthsPerPage at which this item is visible (12, 6, 3, 1)
    var zoomLevel: Int = 12

    var yearDocument: YearDocument?

    init(type: CanvasItemType,
         relativeX: Double = 0,
         relativeY: Double = 0,
         relativeWidth: Double = 0.1,
         relativeHeight: Double = 0.1,
         rotation: Double = 0,
         zIndex: Int = 0,
         opacity: Double = 1.0,
         zoomLevel: Int = 12) {
        self.type = type.rawValue
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.relativeWidth = relativeWidth
        self.relativeHeight = relativeHeight
        self.rotation = rotation
        self.zIndex = zIndex
        self.opacity = opacity
        self.zoomLevel = zoomLevel
        self.createdAt = Date()
    }

    // MARK: - Factory methods

    static func newImage(fileName: String, thumbnail: Data, zIndex: Int) -> CanvasItem {
        let item = CanvasItem(type: .image, relativeX: 0.3, relativeY: 0.3,
                              relativeWidth: 0.15, relativeHeight: 0.2, zIndex: zIndex)
        item.imageFileName = fileName
        item.thumbnailData = thumbnail
        return item
    }

    static func newText(zIndex: Int) -> CanvasItem {
        let item = CanvasItem(type: .text, relativeX: 0.4, relativeY: 0.4,
                              relativeWidth: 0.15, relativeHeight: 0.05, zIndex: zIndex)
        item.text = String(localized: "New Text")
        item.fontSize = 60
        item.textColor = "#333333"
        return item
    }

    static func newShape(_ shapeType: String, zIndex: Int) -> CanvasItem {
        let item = CanvasItem(type: .shape, relativeX: 0.4, relativeY: 0.4,
                              relativeWidth: 0.08, relativeHeight: 0.08, zIndex: zIndex)
        item.shapeType = shapeType
        item.fillColor = "#4A90D9"
        item.strokeColor = "#2C5F8A"
        item.strokeWidth = 2
        return item
    }

    static func newSticker(_ name: String, zIndex: Int) -> CanvasItem {
        let item = CanvasItem(type: .sticker, relativeX: 0.45, relativeY: 0.45,
                              relativeWidth: 0.04, relativeHeight: 0.06, zIndex: zIndex)
        item.stickerName = name
        item.fontSize = 40
        return item
    }
}
