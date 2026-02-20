import SwiftUI
import SwiftData

@main
struct PetalsApp: App {
    @State private var clipboardManager = ClipboardManager()
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            YearDocument.self,
            CanvasItem.self,
            VisionBoard.self,
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
                .environment(clipboardManager)
                .task { migrateOrphanVisionBoardItems() }
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

    /// 기존 board == nil인 VisionBoardItem을 기본 보드로 마이그레이션 (멱등)
    private func migrateOrphanVisionBoardItems() {
        let context = sharedModelContainer.mainContext
        let boardDescriptor = FetchDescriptor<VisionBoard>()
        let boardCount = (try? context.fetchCount(boardDescriptor)) ?? 0

        // 이미 보드가 존재하면 고아 아이템만 처리
        let defaultBoard: VisionBoard
        if boardCount > 0 {
            // 고아 아이템 확인
            let orphanDescriptor = FetchDescriptor<VisionBoardItem>(predicate: #Predicate { $0.board == nil })
            let orphans = (try? context.fetch(orphanDescriptor)) ?? []
            guard !orphans.isEmpty else { return }
            // 첫 번째 보드에 연결
            var sortedDescriptor = FetchDescriptor<VisionBoard>(sortBy: [SortDescriptor(\VisionBoard.sortIndex)])
            defaultBoard = (try? context.fetch(sortedDescriptor))?.first ?? VisionBoard(name: "나의 보드")
            for item in orphans {
                defaultBoard.appendItem(item)
            }
        } else {
            // 보드가 없으면 기본 보드 생성
            defaultBoard = VisionBoard(name: "나의 보드", sortIndex: 0)
            context.insert(defaultBoard)

            let allItems = (try? context.fetch(FetchDescriptor<VisionBoardItem>())) ?? []
            for item in allItems {
                defaultBoard.appendItem(item)
            }
        }
    }
}
