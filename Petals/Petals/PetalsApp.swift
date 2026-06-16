import SwiftUI
import SwiftData

@main
struct PetalsApp: App {
    /// 메인 창 식별자. 메뉴에서 닫힌 창을 다시 열 때 사용.
    static let mainWindowID = "main"

    @State private var clipboardManager = ClipboardManager()
    @State private var premiumStore = PremiumStore()
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            YearDocument.self,
            CanvasItem.self,
            VisionBoard.self,
            VisionBoardItem.self,
        ])
        if ScreenshotConfig.isActive {
            // Screenshot mode: clean in-memory store, no CloudKit, no user data.
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Screenshot in-memory ModelContainer failed: \(error)")
            }
        }

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
        Window("Petals", id: Self.mainWindowID) {
            ContentView()
                .environment(clipboardManager)
                .environment(premiumStore)
                .task {
                    if ScreenshotConfig.isActive {
                        ScreenshotConfig.seedDemoBoards(in: sharedModelContainer.mainContext)
                    } else {
                        migrateOrphanVisionBoardItems()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            PetalsWindowCommands()
            CommandGroup(replacing: .pasteboard) {
                Button("복사") {
                    NotificationCenter.default.post(name: .performCopy, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                Button("붙여넣기") {
                    NotificationCenter.default.post(name: .performPaste, object: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
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
            let sortedDescriptor = FetchDescriptor<VisionBoard>(sortBy: [SortDescriptor(\VisionBoard.sortIndex)])
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
        try? context.save()
    }
}

/// 메인 창을 닫은 뒤에도 메뉴에서 다시 열 수 있도록 하는 커맨드.
/// (App Store 가이드라인 4: 메인 창 재오픈 메뉴 항목 요구사항 대응)
private struct PetalsWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Petals 창 열기") {
                openWindow(id: PetalsApp.mainWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}
