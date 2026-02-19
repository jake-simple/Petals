import SwiftUI
import SwiftData

@main
struct PetalsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            YearDocument.self,
            CanvasItem.self,
            VisionBoardItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // CloudKit 실패 시 로컬 전용으로 폴백
            print("CloudKit ModelContainer failed: \(error). Falling back to local-only.")
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    let current = UserDefaults.standard.double(forKey: "eventFontSize")
                    let size = current > 0 ? current : AppSettings.eventFontSizeDefault
                    UserDefaults.standard.set(min(size + 1, 20), forKey: "eventFontSize")
                }
                .keyboardShortcut("=", modifiers: [.command, .option])
                Button("Decrease Font Size") {
                    let current = UserDefaults.standard.double(forKey: "eventFontSize")
                    let size = current > 0 ? current : AppSettings.eventFontSizeDefault
                    UserDefaults.standard.set(max(size - 1, 6), forKey: "eventFontSize")
                }
                .keyboardShortcut("-", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
