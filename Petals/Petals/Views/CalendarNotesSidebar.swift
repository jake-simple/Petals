import SwiftUI
import SwiftData

struct CalendarNotesSidebar: View {
    let notes: [CalendarNote]
    let focusedDateKey: Int?
    let focusRequest: Int
    let onSelect: (CalendarNote) -> Void
    let onAdd: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var expandedID: String?
    @FocusState private var focusedEditorID: String?
    @State private var errorMessage: String?
    @State private var pendingDeletion: CalendarNote?

    private var groups: [(key: Int, notes: [CalendarNote])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = notes.filter { trimmed.isEmpty || $0.body.localizedStandardContains(trimmed) }
        return Dictionary(grouping: matching, by: \.dateKey)
            .map { (key: $0.key, notes: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Search notes", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("noteSearch")
                Button(action: onAdd) { Image(systemName: "plus") }
                    .accessibilityLabel("Add Note")
            }
            if groups.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No Notes" : "No Matching Notes", systemImage: "note.text")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(groups, id: \.key) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    if let first = group.notes.first {
                                        Text(first.date, format: .dateTime.year().month().day().weekday())
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    ForEach(group.notes) { note in
                                        VStack(alignment: .leading, spacing: 8) {
                                            if expandedID != note.id {
                                                Button {
                                                    expandedID = note.id
                                                    onSelect(note)
                                                } label: {
                                                    Text(note.body.isEmpty ? String(localized: "New Note") : note.body)
                                                        .lineLimit(3)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            if expandedID == note.id {
                                                TextEditor(text: Binding(get: { note.body }, set: {
                                                    note.body = $0
                                                    note.modifiedAt = Date()
                                                }))
                                                .focused($focusedEditorID, equals: note.id)
                                                .task(id: focusRequest) {
                                                    // Let the date-navigation scroll finish before focusing
                                                    // the newly inserted native text editor.
                                                    do { try await Task.sleep(for: .milliseconds(150)) }
                                                    catch { return }
                                                    focusedEditorID = note.id
                                                }
                                                .scrollContentBackground(.hidden)
                                                .font(.system(size: 14))
                                                .lineSpacing(4)
                                                .frame(minHeight: 100, maxHeight: 220)
                                                .accessibilityLabel("Note")
                                                HStack {
                                                    Button("Delete", role: .destructive) { pendingDeletion = note }
                                                    Spacer()
                                                    Button("Done") { save(); focusedEditorID = nil; expandedID = nil }
                                                }
                                            }
                                        }
                                        .padding(10)
                                        .background(group.key == focusedDateKey ? Color.clear : Color.primary.opacity(0.06),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                .padding(4)
                                .background(group.key == focusedDateKey ? Color.accentColor.opacity(0.10) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .id(group.key)
                            }
                        }
                    }
                    .task {
                        await Task.yield()
                        scrollToFocus(proxy)
                    }
                    .onChange(of: focusRequest) {
                        query = ""
                        Task { @MainActor in
                            await Task.yield()
                            scrollToFocus(proxy)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: focusRequest) { query = "" }
        .onDisappear { save() }
        .confirmationDialog("Delete this note?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let note = pendingDeletion { modelContext.delete(note); save() }
                pendingDeletion = nil
            }
        }
        .alert("Unable to Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func save() {
        do { try modelContext.save() } catch { errorMessage = error.localizedDescription }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let todayKey = (today.year ?? 2000) * 10000 + (today.month ?? 1) * 100 + (today.day ?? 1)
        let target = focusedDateKey ?? groups.first(where: { $0.key >= todayKey })?.key ?? groups.last?.key
        if let target { proxy.scrollTo(target, anchor: .top) }
    }
}

struct NewCalendarNoteView: View {
    let initialDate: Date
    let onSave: (Date, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Note").font(.headline)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextEditor(text: $text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 150)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .accessibilityLabel("Note")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(date, text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { date = initialDate }
    }
}
