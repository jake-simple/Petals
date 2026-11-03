import Foundation
import SwiftData

@MainActor
enum PlanningBoardOperations {
    static func duplicate(_ source: PlanningBoard, name: String, in context: ModelContext) throws -> PlanningBoard {
        let copy = PlanningBoard(name: name, theme: source.theme)
        copy.calendarSelectionData = source.calendarSelectionData
        context.insert(copy)
        let sourceID = source.id
        let documents = try context.fetch(FetchDescriptor<YearDocument>(predicate: #Predicate { $0.boardID == sourceID }))
        for original in documents {
            let document = YearDocument(year: original.year, theme: original.theme)
            document.boardID = copy.id
            context.insert(document)
            for item in original.canvasItems ?? [] {
                let clone = CanvasItem(type: CanvasItemType(rawValue: item.type) ?? .text,
                                       relativeX: item.relativeX, relativeY: item.relativeY,
                                       relativeWidth: item.relativeWidth, relativeHeight: item.relativeHeight,
                                       rotation: item.rotation, zIndex: item.zIndex, opacity: item.opacity,
                                       zoomLevel: item.zoomLevel, pageIndex: item.pageIndex)
                CanvasItemSnapshot(from: item, containerSize: CGSize(width: 1, height: 1)).applyContent(to: clone)
                // Copies must own their image file: deleting either board's decoration
                // must not remove an image still used by the other board.
                if item.originalImageData == nil, let file = item.imageFileName {
                    guard let copied = ImageManager.copyImageFile(fileName: file) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    clone.imageFileName = copied
                }
                document.appendItem(clone)
            }
        }
        let notes = try context.fetch(FetchDescriptor<CalendarNote>(predicate: #Predicate { $0.boardID == sourceID }))
        for original in notes {
            let note = CalendarNote(boardID: copy.id, date: original.date, body: original.body)
            note.year = original.year
            note.month = original.month
            note.day = original.day
            context.insert(note)
        }
        try context.save()
        return copy
    }

    static func delete(_ board: PlanningBoard, in context: ModelContext) throws {
        // Preserve a synced tombstone so a not-yet-migrated Mac cannot recreate it.
        board.deletedAt = Date()
        let id = board.id
        let documents = try context.fetch(FetchDescriptor<YearDocument>(predicate: #Predicate { $0.boardID == id }))
        for document in documents { context.delete(document) }
        let notes = try context.fetch(FetchDescriptor<CalendarNote>(predicate: #Predicate { $0.boardID == id }))
        for note in notes { context.delete(note) }
        try context.save()
    }
}
