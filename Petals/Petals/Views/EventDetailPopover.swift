import SwiftUI
import EventKit

struct EventDetailPopover: View {
    let event: EKEvent
    let onEdit: () -> Void
    let onDelete: (EKSpan) -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + calendar color
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 10, height: 10)
                Text(event.title ?? String(localized: "Untitled"))
                    .font(.headline)
            }

            // Calendar name
            Text(event.calendar.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Dates
            if let start = event.startDate, let end = event.endDate {
                if event.isAllDay {
                    if Calendar.current.isDate(start, inSameDayAs: end.addingTimeInterval(-1)) {
                        Text(start.formatted(date: .long, time: .omitted))
                    } else {
                        let adjustedEnd = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
                        Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(adjustedEnd.formatted(date: .abbreviated, time: .omitted))")
                    }
                } else {
                    Text("\(start.formatted()) – \(end.formatted())")
                }
            }

            // Notes
            if let notes = event.notes, !notes.isEmpty {
                Divider()
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            Divider()

            HStack {
                Button("Edit") { onEdit() }
                Spacer()
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .padding()
        .frame(width: 260)
        .confirmationDialog("Delete this event?", isPresented: $showDeleteConfirm) {
            if event.hasRecurrenceRules {
                Button("This Event Only", role: .destructive) { onDelete(.thisEvent) }
                Button("All Future Events", role: .destructive) { onDelete(.futureEvents) }
            } else {
                Button("Delete", role: .destructive) { onDelete(.thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
