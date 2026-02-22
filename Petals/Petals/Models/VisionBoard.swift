import Foundation
import SwiftData

@Model
final class VisionBoard {
    var name: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var sortIndex: Int = 0

    // 보드별 뷰포트 상태
    var viewportScale: Double = 1.0
    var viewportOffsetX: Double = 0.0
    var viewportOffsetY: Double = 0.0

    @Relationship(deleteRule: .cascade, inverse: \VisionBoardItem.board)
    var items: [VisionBoardItem]?

    init(name: String, sortIndex: Int = 0) {
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    func appendItem(_ item: VisionBoardItem) {
        if items == nil { items = [] }
        items?.append(item)
    }

    func removeItem(where predicate: (VisionBoardItem) -> Bool) {
        items?.removeAll(where: predicate)
    }

    var nextZIndex: Int {
        ((items ?? []).map(\.zIndex).max() ?? 0) + 1
    }

    var minZIndex: Int {
        ((items ?? []).map(\.zIndex).min() ?? 0) - 1
    }
}
