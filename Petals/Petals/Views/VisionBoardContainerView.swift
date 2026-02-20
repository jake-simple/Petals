import SwiftUI
import SwiftData

struct VisionBoardContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VisionBoard.sortIndex) private var boards: [VisionBoard]
    @Binding var selectedBoardID: PersistentIdentifier?
    @State private var editingBoardID: PersistentIdentifier?
    @State private var boardCreationError: String?
    @FocusState private var listFocused: Bool

    private var selectedBoard: VisionBoard? {
        guard let id = selectedBoardID else { return nil }
        return boards.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let board = selectedBoard {
                VisionBoardView(board: board)
                    .id(board.persistentModelID)
            } else {
                ContentUnavailableView("보드를 선택하세요",
                                       systemImage: "rectangle.3.group",
                                       description: Text("사이드바에서 보드를 선택하거나 새 보드를 만드세요."))
            }
        }
        .onAppear {
            // nil → 값으로 전환해야 List가 selection 변경을 감지해 하이라이트 적용
            let id = selectedBoardID ?? boards.first?.persistentModelID
            guard id != nil else { return }
            selectedBoardID = nil
            Task { @MainActor in
                listFocused = true
                selectedBoardID = id
            }
        }
        .onChange(of: boards) { _, _ in autoSelectFirstBoard() }
        .onChange(of: selectedBoardID) { _, newID in
            if let editingID = editingBoardID, editingID != newID {
                editingBoardID = nil
            }
        }
        .toolbar(removing: .sidebarToggle)
        .alert("보드를 만들 수 없습니다", isPresented: boardCreationErrorBinding) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(boardCreationError ?? "알 수 없는 오류가 발생했습니다.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedBoardID) {
                ForEach(boards) { board in
                    BoardRow(
                        board: board,
                        editingBoardID: $editingBoardID,
                        onSelect: { selectedBoardID = board.persistentModelID },
                        onDelete: { deleteBoard(board) }
                    )
                    .tag(board.persistentModelID)
                }
            }
            .listStyle(.sidebar)
            .focused($listFocused)
            .safeAreaInset(edge: .top) {
                Spacer().frame(height: 8)
            }


            Button(action: addBoard) {
                Label("새 보드", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 450)
    }

    // MARK: - Actions

    private func autoSelectFirstBoard() {
        if selectedBoard == nil, let first = boards.first {
            selectedBoardID = first.persistentModelID
        }
    }

    private func addBoard() {
        let maxSort = boards.map(\.sortIndex).max() ?? 0
        let board = VisionBoard(name: "새 보드", sortIndex: maxSort + 1)
        modelContext.insert(board)

        do {
            try modelContext.save()
        } catch {
            boardCreationError = "새 보드 저장에 실패했습니다. 잠시 후 다시 시도해 주세요."
            print("Failed to save new board: \(error)")
            return
        }

        selectedBoardID = board.persistentModelID
        editingBoardID = board.persistentModelID
    }

    private func deleteBoard(_ board: VisionBoard) {
        for item in board.items ?? [] {
            if let fileName = item.imageFileName {
                ImageManager.deleteImage(fileName: fileName)
            }
        }

        let wasSelected = selectedBoardID == board.persistentModelID
        modelContext.delete(board)

        if wasSelected {
            selectedBoardID = boards.first(where: { $0.persistentModelID != board.persistentModelID })?.persistentModelID
        }

        try? modelContext.save()
    }

    private var boardCreationErrorBinding: Binding<Bool> {
        Binding(
            get: { boardCreationError != nil },
            set: { isPresented in
                if !isPresented {
                    boardCreationError = nil
                }
            }
        )
    }
}

// MARK: - Board Row

private struct BoardRow: View {
    @Bindable var board: VisionBoard
    @Binding var editingBoardID: PersistentIdentifier?
    var onSelect: () -> Void
    var onDelete: () -> Void
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        if editingBoardID == board.persistentModelID {
            TextField("보드 이름", text: $board.name)
                .focused($textFieldFocused)
                .onSubmit { editingBoardID = nil }
                .onExitCommand { editingBoardID = nil }
                .onAppear { textFieldFocused = true }
        } else {
            Text(board.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                }
                .contextMenu {
                    Button("이름 변경") {
                        onSelect()
                        editingBoardID = board.persistentModelID
                    }
                    Divider()
                    Button("삭제", role: .destructive) {
                        onDelete()
                    }
                }
        }
    }
}
