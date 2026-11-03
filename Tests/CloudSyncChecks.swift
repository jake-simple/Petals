import AppKit
import SwiftData
import CoreData
import CloudKit
import Security

/// Run only in a separately signed Development-environment test bundle.
/// Independent stores prove CloudKit transport, not physical second-device behavior.
@main
struct CloudSyncChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task {
            do { try await run(); exit(0) }
            catch { log("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }

    static func log(_ message: String) { print(message); fflush(stdout) }

    static func requireDevelopmentEntitlement() throws {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              entitlements["com.apple.developer.icloud-container-environment"] as? String == "Development" else {
            throw NSError(domain: "CloudSyncChecks", code: 6, userInfo: [NSLocalizedDescriptionKey: "Refusing CloudKit access: explicit Development signing entitlement required"])
        }
    }

    @MainActor static func run() async throws {
        try requireDevelopmentEntitlement()
        if CommandLine.arguments.dropFirst().first == "check-environment" {
            log("PASS: signed Development environment; no CloudKit records accessed")
            return
        }
        guard CommandLine.arguments.count == 4,
              let runID = UUID(uuidString: CommandLine.arguments[2]),
              ["writer", "reader"].contains(CommandLine.arguments[3]) else {
            throw NSError(domain: "CloudSyncChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: seed|read|update|read-update|delete|read-delete UUID writer|reader"])
        }
        let mode = CommandLine.arguments[1]
        let boardID = "sync-check-" + runID.uuidString
        let side = CommandLine.arguments[3]
        guard try await CKContainer(identifier: "iCloud.com.onessa.Petals").accountStatus() == .available else {
            throw NSError(domain: "CloudSyncChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "iCloud unavailable"])
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PetalsSyncChecks/" + runID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema([PlanningBoard.self, CalendarNote.self, YearDocument.self, CanvasItem.self, VisionBoard.self, VisionBoardItem.self])
        let config = ModelConfiguration(schema: schema, url: root.appendingPathComponent(side + ".store"), cloudKitDatabase: .private("iCloud.com.onessa.Petals"))
        let token = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            log("CloudKit event type=\(event.type.rawValue) success=\(event.succeeded) error=\(String(describing: event.error))")
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        log("Opened isolated \(side) store; mode=\(mode); run=\(runID.uuidString)")
        let payload = Data((0..<262144).map { UInt8(truncatingIfNeeded: $0 * 31) })
        if mode == "seed" {
            guard try context.fetch(FetchDescriptor<PlanningBoard>(predicate: #Predicate { $0.id == boardID })).isEmpty else {
                throw NSError(domain: "CloudSyncChecks", code: 3, userInfo: [NSLocalizedDescriptionKey: "Fixture already exists"])
            }
            let board = PlanningBoard(id: boardID, name: "동기화 검증 " + runID.uuidString, theme: "tokyo-night")
            var reference = PlanningCalendarReference(legacyIdentifier: "fixture-calendar")
            reference.title = "검증 Calendar"
            reference.sourceTitle = "iCloud"
            board.calendarSelection = [reference]
            context.insert(board)
            let document = YearDocument(year: 2027)
            document.boardID = boardID
            context.insert(document)
            let image = CanvasItem(type: .image, relativeX: 0.25, rotation: 12, zIndex: 4)
            image.originalImageData = payload
            document.appendItem(image)
            let note = CalendarNote(boardID: boardID, date: Calendar.current.date(from: DateComponents(year: 2027, month: 2, day: 3))!, body: "여행 준비 — sync fixture")
            context.insert(note)
            try context.save()
            log("Saved board/calendar reference/date note/decoration/256KiB asset fixture")
        } else if mode == "update" || mode == "delete" {
            guard let board = try context.fetch(FetchDescriptor<PlanningBoard>(predicate: #Predicate { $0.id == boardID })).first else {
                throw NSError(domain: "CloudSyncChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "Fixture absent in this store"])
            }
            let notes = try context.fetch(FetchDescriptor<CalendarNote>(predicate: #Predicate { $0.boardID == boardID }))
            if mode == "update" {
                board.name = "Edited from reader"
                board.updatedAt = Date()
                for note in notes { note.body = "수정됨 — edited"; note.modifiedAt = Date() }
            } else {
                board.deletedAt = Date()
                for note in notes { context.delete(note) }
                for doc in try context.fetch(FetchDescriptor<YearDocument>(predicate: #Predicate { $0.boardID == boardID })) { context.delete(doc) }
            }
            try context.save()
            log("Saved fixture \(mode)")
        }
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if mode.hasPrefix("read") {
                let fresh = ModelContext(container)
                let boards = try fresh.fetch(FetchDescriptor<PlanningBoard>(predicate: #Predicate { $0.id == boardID }))
                let notes = try fresh.fetch(FetchDescriptor<CalendarNote>(predicate: #Predicate { $0.boardID == boardID }))
                let docs = try fresh.fetch(FetchDescriptor<YearDocument>(predicate: #Predicate { $0.boardID == boardID }))
                if let board = boards.first {
                    let valid: Bool
                    if mode == "read-delete" {
                        valid = board.deletedAt != nil && notes.isEmpty && docs.isEmpty
                    } else if mode == "read-update" {
                        valid = board.name == "Edited from reader" && notes.first?.body == "수정됨 — edited"
                    } else {
                        valid = board.theme == "tokyo-night" && board.calendarSelection.first?.title == "검증 Calendar" &&
                            notes.first?.dateKey == 20270203 && notes.first?.body == "여행 준비 — sync fixture" &&
                            docs.first?.canvasItems?.first?.originalImageData == payload &&
                            docs.first?.canvasItems?.first?.relativeX == 0.25 && docs.first?.canvasItems?.first?.rotation == 12
                    }
                    if valid { log("PASS: \(mode) through independent \(side) store"); return }
                }
            }
            try await Task.sleep(for: .seconds(3))
        }
        if mode.hasPrefix("read") {
            throw NSError(domain: "CloudSyncChecks", code: 5, userInfo: [NSLocalizedDescriptionKey: "Remote import did not reach expected state within 180 seconds"])
        }
        log("Writer observation ended; export events alone do not prove reader arrival")
    }
}
