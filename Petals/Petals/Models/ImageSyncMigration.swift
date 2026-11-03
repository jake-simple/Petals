import Foundation
import SwiftData

@MainActor
enum ImageSyncMigration {
    /// Add originals to the synced records. Do not mark missing files migrated:
    /// the next foreground pass retries after iCloud Drive downloads complete.
    static func migrate(in context: ModelContext) async throws {
        let canvas = try context.fetch(FetchDescriptor<CanvasItem>())
        for item in canvas where item.originalImageData == nil {
            if let file = item.imageFileName, let data = await ImageManager.originalData(fileName: file),
               item.modelContext != nil {
                item.originalImageData = data
            }
        }
        let boards = try context.fetch(FetchDescriptor<VisionBoardItem>())
        for item in boards where item.originalImageData == nil {
            if let file = item.imageFileName, let data = await ImageManager.originalData(fileName: file),
               item.modelContext != nil {
                item.originalImageData = data
            }
        }
        try context.save()
    }
}
