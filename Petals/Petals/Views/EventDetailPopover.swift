import SwiftUI
import EventKit

struct EventDetailPopover: View {
    let event: EKEvent
    let onEdit: () -> Void
    let onDelete: (EKSpan) -> Void

    @State private var showDeleteConfirm = false

    private var calendarColor: Color {
        Color(cgColor: event.calendar.cgColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color accent bar
            calendarColor
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                // Title
                Text(event.title ?? String(localized: "Untitled"))
                    .font(.title3.weight(.semibold))

                // Calendar name
                HStack(spacing: 6) {
                    Circle()
                        .fill(calendarColor)
                        .frame(width: 8, height: 8)
                    Text(event.calendar.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Date & time
                if let start = event.startDate, let end = event.endDate {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formattedDateRange(start: start, end: end))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Recurrence
                if event.hasRecurrenceRules, let rule = event.recurrenceRules?.first {
                    HStack(spacing: 6) {
                        Image(systemName: "repeat")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(recurrenceDescription(rule))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Notes
                if let notes = event.notes, !notes.isEmpty {
                    Divider()
                    ScrollView {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }

                Divider()

                // Actions
                HStack {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .destructive, action: { showDeleteConfirm = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .frame(width: 280)
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

    private func recurrenceDescription(_ rule: EKRecurrenceRule) -> String {
        let interval = rule.interval
        let base: String
        switch rule.frequency {
        case .daily:
            base = interval == 1 ? String(localized: "Every day") : String(localized: "Every \(interval) days")
        case .weekly:
            let weekBase = interval == 1 ? String(localized: "Every week") : String(localized: "Every \(interval) weeks")
            if let days = rule.daysOfTheWeek, !days.isEmpty {
                let names = days.map { weekdayName($0.dayOfTheWeek) }
                return "\(weekBase) (\(names.joined(separator: ", ")))"
            }
            base = weekBase
        case .monthly:
            base = interval == 1 ? String(localized: "Every month") : String(localized: "Every \(interval) months")
        case .yearly:
            base = interval == 1 ? String(localized: "Every year") : String(localized: "Every \(interval) years")
        @unknown default:
            base = String(localized: "Repeats")
        }
        return base
    }

    private func weekdayName(_ day: EKWeekday) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        switch day {
        case .sunday: return symbols[0]
        case .monday: return symbols[1]
        case .tuesday: return symbols[2]
        case .wednesday: return symbols[3]
        case .thursday: return symbols[4]
        case .friday: return symbols[5]
        case .saturday: return symbols[6]
        @unknown default: return "?"
        }
    }

    private func formattedDateRange(start: Date, end: Date) -> String {
        if event.isAllDay {
            if Calendar.current.isDate(start, inSameDayAs: end.addingTimeInterval(-1)) {
                return start.formatted(date: .long, time: .omitted)
            } else {
                let adjustedEnd = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
                return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(adjustedEnd.formatted(date: .abbreviated, time: .omitted))"
            }
        } else {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return "\(start.formatted(date: .long, time: .omitted))  \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
            }
            return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}
