import SwiftUI
import EventKit

struct CalendarFilterView: View {
    @Bindable var eventManager: EventManager

    private var groupedCalendars: [(sourceTitle: String, sourceID: String, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: eventManager.calendars) {
            $0.source?.sourceIdentifier ?? "unknown"
        }
        return grouped
            .map { entry in
                let title = entry.value.first?.source?.title ?? "Other"
                return (sourceTitle: title, sourceID: entry.key, calendars: entry.value)
            }
            .sorted { $0.sourceTitle.localizedCompare($1.sourceTitle) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendars")
                .font(.headline)

            ForEach(groupedCalendars, id: \.sourceID) { group in
                Text(group.sourceTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: binding(for: calendar)) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 10, height: 10)
                            Text(calendar.title)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if eventManager.calendars.isEmpty {
                Text("No calendars available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding {
            eventManager.selectedCalendarIDs.contains(calendar.calendarIdentifier)
        } set: { isOn in
            if isOn {
                eventManager.selectedCalendarIDs.insert(calendar.calendarIdentifier)
            } else {
                eventManager.selectedCalendarIDs.remove(calendar.calendarIdentifier)
            }
        }
    }
}
