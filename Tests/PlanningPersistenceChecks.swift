import Foundation
import AppKit
import SwiftData

/// Standalone integration check; uses an isolated SQLite store and preference suite.
@main
struct PlanningPersistenceChecks {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "Petals.PersistenceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let schema = Schema([YearDocument.self, CanvasItem.self, PlanningBoard.self, CalendarNote.self, VisionBoard.self, VisionBoardItem.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let old = YearDocument(year: 2025, theme: "test-theme")
        let decoration = CanvasItem.newText(zIndex: 4)
        decoration.text = "가족 여행 — Family trip"
        old.appendItem(decoration)
        context.insert(old)
        try context.save()
        let sets = [CalendarSet(id: "default", name: "기본", calendarIDs: ["calendar-a"]),
                    CalendarSet(id: "family", name: "가족", calendarIDs: ["calendar-b"])]
        defaults.set(try JSONEncoder().encode(sets), forKey: "calendarSets")
        defaults.set("family", forKey: "activeCalendarSetID")
        let active = try PlanningBoardMigration.migrate(in: context, defaults: defaults)
        precondition(active == "legacy-set-family")
        precondition(old.boardID == active)
        precondition(old.theme == "test-theme")
        precondition(old.canvasItems?.first?.text == decoration.text)
        let boards = try context.fetch(FetchDescriptor<PlanningBoard>())
        precondition(boards.count == 2)
        precondition(boards.first { $0.id == active }?.calendarSelection.first?.identifier == "calendar-b")
        _ = try PlanningBoardMigration.migrate(in: context, defaults: defaults)
        precondition(tryCount(context) == 2, "Migration must be idempotent")
        let date = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 2))!
        let note = CalendarNote(boardID: active, date: date, body: "준비물\nPacking list")
        context.insert(note)
        try context.save()
        let reopened = try ModelContainer(for: schema, configurations: config)
        let second = ModelContext(reopened)
        let notes = try second.fetch(FetchDescriptor<CalendarNote>())
        precondition(notes.count == 1 && notes[0].body == "준비물\nPacking list")
        precondition(notes[0].dateKey == 20270102 && notes[0].boardID == active)
        precondition(tryCount(second) == 2)
        let originalBoard = boards.first { $0.id == active }!
        let image = CanvasItem.newImage(fileName: "not-on-disk.jpg", thumbnail: Data([1, 2]),
                                       original: Data(repeating: 83, count: 200_000), zIndex: 3)
        old.appendItem(image)
        try context.save()
        let copy = try PlanningBoardOperations.duplicate(originalBoard, name: "복사본", in: context)
        precondition(copy.id != originalBoard.id && copy.calendarSelection == originalBoard.calendarSelection)
        let copiedDocuments = try context.fetch(FetchDescriptor<YearDocument>()).filter { $0.boardID == copy.id }
        precondition(copiedDocuments.count == 1)
        precondition(copiedDocuments[0].canvasItems?.count == 2)
        precondition(copiedDocuments[0].canvasItems?.first { $0.type == "image" }?.originalImageData == image.originalImageData)
        let copiedNotes = try context.fetch(FetchDescriptor<CalendarNote>()).filter { $0.boardID == copy.id }
        precondition(copiedNotes.count == 1 && copiedNotes[0].id != note.id)
        copiedNotes[0].body = "독립 수정"
        try context.save()
        precondition(note.body == "준비물\nPacking list")
        try PlanningBoardOperations.delete(copy, in: context)
        precondition(copy.deletedAt != nil)
        let originalNotes = try context.fetch(FetchDescriptor<CalendarNote>()).filter { $0.boardID == active }
        precondition(originalNotes.count == 1)
        let imageReopen = try ModelContainer(for: schema, configurations: config)
        let persistedImages = try imageReopen.mainContext.fetch(FetchDescriptor<CanvasItem>()).filter { $0.type == "image" }
        precondition(persistedImages.count == 1 && persistedImages[0].originalImageData == image.originalImageData)
        if CommandLine.arguments.count > 1 {
            let legacyConfig = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
            let legacyStore = try ModelContainer(for: schema, configurations: legacyConfig)
            let migrated = try legacyStore.mainContext.fetch(FetchDescriptor<YearDocument>())
            precondition(migrated.count == 1 && migrated[0].year == 2024 && migrated[0].theme == "legacy-theme")
            precondition(migrated[0].canvasItems?.first?.text == "이전 데이터 Legacy")
            precondition(migrated[0].canvasItems?.first?.relativeX == 0.23)
            precondition(migrated[0].boardID.isEmpty)
            let whiteboardCount = try legacyStore.mainContext.fetchCount(FetchDescriptor<VisionBoard>())
            precondition(whiteboardCount == 1)
            print("PASS: actual old compiled schema migrated without losing document, decoration, or whiteboard")
        }
        let offlineA = PlanningBoard(id: "offline-same", name: "Older")
        let offlineB = PlanningBoard(id: "offline-same", name: "Newer")
        offlineA.updatedAt = Date(timeIntervalSince1970: 10)
        offlineB.updatedAt = Date(timeIntervalSince1970: 20)
        context.insert(offlineA)
        context.insert(offlineB)
        let a = YearDocument(year: 2028)
        let b = YearDocument(year: 2028)
        a.boardID = offlineA.id
        b.boardID = offlineB.id
        a.appendItem(CanvasItem.newText(zIndex: 1))
        b.appendItem(CanvasItem.newText(zIndex: 2))
        context.insert(a)
        context.insert(b)
        try context.save()
        let countBefore = try context.fetchCount(FetchDescriptor<PlanningBoard>())
        let projection = PlanningBoardProjection.visibleBoards([offlineA, offlineB])
        precondition(projection.count == 1 && projection[0].name == "Newer")
        precondition(PlanningBoardProjection.canvasItems(in: [a, b]).count == 2)
        offlineA.deletedAt = Date()
        precondition(PlanningBoardProjection.visibleBoards([offlineA, offlineB]).isEmpty)
        let countAfter = try context.fetchCount(FetchDescriptor<PlanningBoard>())
        precondition(countAfter == countBefore, "Read projection must not delete original records")
        precondition(a.canvasItems?.count == 1 && b.canvasItems?.count == 1)
        let recoveryName = "petals-recovery-check-" + UUID().uuidString + ".png"
        let recoveryURL = ImageManager.imagesDirectory.appendingPathComponent(recoveryName)
        defer { try? FileManager.default.removeItem(at: recoveryURL) }
        let recoveryItem = CanvasItem(type: .image)
        recoveryItem.imageFileName = recoveryName
        context.insert(recoveryItem)
        try context.save()
        try await ImageSyncMigration.migrate(in: context)
        precondition(recoveryItem.originalImageData == nil, "Missing originals must remain retryable")
        let recoveryBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<2 { for y in 0..<2 { recoveryBitmap.setColor(.red, atX: x, y: y) } }
        let recoveryData = recoveryBitmap.representation(using: .png, properties: [:])!
        try recoveryData.write(to: recoveryURL, options: .atomic)
        try await ImageSyncMigration.migrate(in: context)
        precondition(recoveryItem.originalImageData == recoveryData, "Later available original must migrate")
        try await ImageSyncMigration.migrate(in: context)
        precondition(recoveryItem.originalImageData == recoveryData && FileManager.default.fileExists(atPath: recoveryURL.path))
        print("PASS: missing original remains retryable; later file recovers; repeated migration preserves original file and data")
        print("PASS: non-destructive duplicate projection preserves both original rows and all decoration content; tombstone hides logical board")
        print("PASS: board duplication/isolation/deletion and external original-image persistence")
        print("PASS: legacy set/document migration, decoration/theme preservation, idempotency, Korean/English note persistence, civil date, reopened store")
    }

    @MainActor
    static func tryCount(_ context: ModelContext) -> Int {
        try! context.fetchCount(FetchDescriptor<PlanningBoard>())
    }
}
