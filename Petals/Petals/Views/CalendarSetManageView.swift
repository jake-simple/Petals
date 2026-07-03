import SwiftUI

/// Rename, reorder, and delete calendar sets. Membership is edited live in the
/// main filter view (checking calendars edits the active set), so this sheet
/// only handles set-level metadata.
struct CalendarSetManageView: View {
    @Bindable var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Calendar Sets")
                .font(.headline)

            List {
                ForEach(eventManager.calendarSets) { set in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        TextField("Set name", text: nameBinding(for: set))
                            .textFieldStyle(.plain)
                        Spacer()
                        if set.isDefault {
                            Text("Default")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(role: .destructive) {
                                eventManager.deleteSet(id: set.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onMove { indices, newOffset in
                    eventManager.moveSets(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button {
                    eventManager.createSet(name: String(localized: "New Set"),
                                           calendarIDs: [],
                                           activate: false)
                } label: {
                    Label("Add Empty Set", systemImage: "plus")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380, height: 360)
    }

    private func nameBinding(for set: CalendarSet) -> Binding<String> {
        Binding {
            eventManager.calendarSets.first { $0.id == set.id }?.name ?? set.name
        } set: { newValue in
            eventManager.renameSet(id: set.id, to: newValue)
        }
    }
}
