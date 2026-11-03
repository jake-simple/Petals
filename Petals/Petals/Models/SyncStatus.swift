import Foundation
import Observation
import CoreData

@MainActor
@Observable
final class SyncStatus {
    static let shared = SyncStatus()
    var localOnlyReason: String?
    var lastError: String?
    var lastImport: Date?
    var lastExport: Date?

    var message: String {
        if localOnlyReason != nil { return String(localized: "iCloud sync could not start. Changes are saved on this Mac. Restart the app to retry.") }
        if lastError != nil { return String(localized: "iCloud sync is temporarily unavailable. Changes remain saved on this Mac.") }
        if lastImport != nil || lastExport != nil { return String(localized: "iCloud transfer completed") }
        return String(localized: "Waiting for iCloud")
    }

    func receive(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
        if let error = event.error { lastError = error.localizedDescription; return }
        guard event.succeeded else { return }
        lastError = nil
        if event.type == .import { lastImport = event.endDate }
        if event.type == .export { lastExport = event.endDate }
    }
}
