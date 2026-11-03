import Foundation
import SwiftData

@main
struct LegacyStoreSeed {
    @MainActor
    static func main() throws {
        let schema = Schema([YearDocument.self, CanvasItem.self, VisionBoard.self, VisionBoardItem.self])
        let config = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
        let store = try ModelContainer(for: schema, configurations: config)
        let year = YearDocument(year: 2024, theme: "legacy-theme")
        let item = CanvasItem.newText(zIndex: 2)
        item.text = "이전 데이터 Legacy"
        item.relativeX = 0.23
        year.appendItem(item)
        store.mainContext.insert(year)
        let board = VisionBoard(name: "기존 보드")
        store.mainContext.insert(board)
        try store.mainContext.save()
        print("PASS: old compiled schema fixture written")
    }
}
