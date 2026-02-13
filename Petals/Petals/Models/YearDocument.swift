import Foundation
import SwiftData

@Model
final class YearDocument {
    var year: Int = 0
    var theme: String = "minimal-light"
    @Relationship(deleteRule: .cascade, inverse: \CanvasItem.yearDocument)
    var canvasItems: [CanvasItem]?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(year: Int, theme: String = "minimal-light") {
        self.year = year
        self.theme = theme
        self.canvasItems = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    func appendItem(_ item: CanvasItem) {
        if canvasItems == nil { canvasItems = [] }
        canvasItems?.append(item)
    }

    func removeItem(where predicate: (CanvasItem) -> Bool) {
        canvasItems?.removeAll(where: predicate)
    }

    func canvasItems(for zoomLevel: Int) -> [CanvasItem] {
        (canvasItems ?? []).filter { $0.zoomLevel == zoomLevel }
    }

    var nextZIndex: Int {
        ((canvasItems ?? []).map(\.zIndex).max() ?? 0) + 1
    }

    var minZIndex: Int {
        ((canvasItems ?? []).map(\.zIndex).min() ?? 0) - 1
    }
}
