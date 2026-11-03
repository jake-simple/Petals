import SwiftUI

struct PlanningBoardSettingsView: View {
    let board: PlanningBoard
    let canDelete: Bool
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Board Settings").font(.headline)
            TextField("Board name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Duplicate Board") { onDuplicate(); dismiss() }
                Button("Delete Board", role: .destructive) { confirmingDelete = true }
                    .disabled(!canDelete)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onRename(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { name = board.name }
        .confirmationDialog("Delete this board and its notes and decorations?", isPresented: $confirmingDelete) {
            Button("Delete Board", role: .destructive) { onDelete(); dismiss() }
        } message: {
            Text("Calendar events will be kept.")
        }
    }
}
