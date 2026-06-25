import SwiftUI
import EventKit

private struct OnThisDayYearGroup: Identifiable {
    let year: Int
    let events: [EKEvent]
    var id: Int { year }
}

struct EventDetailPopover: View {
    let event: EKEvent
    let eventManager: EventManager
    let onEdit: () -> Void

    @State private var onThisDayGroups: [OnThisDayYearGroup] = []

    private var calendarColor: Color {
        Color(cgColor: event.calendar.cgColor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Color accent bar
                calendarColor
                    .frame(height: 4)

                VStack(alignment: .leading, spacing: 12) {
                    // Title + edit icon
                    HStack(alignment: .top) {
                        Text(event.title ?? String(localized: "Untitled"))
                            .font(.title3.weight(.semibold))

                        Spacer()

                        Button(action: onEdit) {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Calendar name
                    HStack(spacing: 6) {
                        Circle()
                            .fill(calendarColor)
                            .frame(width: 8, height: 8)
                        Text(event.calendar.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    // Date & time
                    if let start = event.startDate, let end = event.endDate {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(formattedDateRange(start: start, end: end))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Recurrence
                    if event.hasRecurrenceRules, let rule = event.recurrenceRules?.first {
                        HStack(spacing: 6) {
                            Image(systemName: "repeat")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(recurrenceDescription(rule))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Location
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(location)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // URL
                    if let url = event.url {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Link(url.absoluteString, destination: url)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    // Participants
                    if let attendees = event.attendees, !attendees.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(attendees.sortedByStatus(), id: \.self) { participant in
                                ParticipantRow(participant: participant)
                            }
                        }
                    }

                    // Notes
                    if let notes = event.notes, !notes.isEmpty {
                        Divider()
                        Text(notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // On This Day
                    if !onThisDayGroups.isEmpty {
                        onThisDaySection
                    }
                }
                .padding()
            }
        }
        .frame(width: 280)
        .task(id: event.eventIdentifier) {
            await loadOnThisDay()
        }
    }

    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Label(String(localized: "이날의 기록"), systemImage: "clock.arrow.circlepath")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(onThisDayGroups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(yearsAgoLabel(group.year))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)

                    ForEach(group.events, id: \.eventIdentifier) { e in
                        OnThisDayEventRow(event: e)
                    }
                }
            }
        }
    }

    private func yearsAgoLabel(_ year: Int) -> String {
        guard let start = event.startDate else { return "\(year)" }
        let currentYear = Calendar.current.component(.year, from: start)
        let diff = currentYear - year
        if diff == 1 {
            return String(localized: "1년 전, \(year)년")
        } else {
            return String(localized: "\(diff)년 전, \(year)년")
        }
    }

    private func loadOnThisDay() async {
        guard let date = event.startDate else { return }
        onThisDayGroups = []
        await eventManager.fetchOnThisDay(for: date) { batch in
            let newGroups = batch.map { OnThisDayYearGroup(year: $0.year, events: $0.events) }
            onThisDayGroups.append(contentsOf: newGroups)
            onThisDayGroups.sort { $0.year > $1.year }
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
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return start.formatted(date: .long, time: .omitted)
            } else {
                return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
            }
        } else {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return "\(start.formatted(date: .long, time: .omitted))  \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
            }
            return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

// MARK: - On This Day Event Row

private struct OnThisDayEventRow: View {
    let event: EKEvent

    private var calendarColor: Color {
        Color(cgColor: event.calendar.cgColor)
    }

    var body: some View {
        HStack(spacing: 6) {
            if event.isAllDay {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(calendarColor)
                    .frame(width: 3, height: 16)
            } else {
                Circle()
                    .fill(calendarColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? String(localized: "Untitled"))
                    .font(.callout)
                    .lineLimit(1)

                if !event.isAllDay, let start = event.startDate {
                    Text(start.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(.secondary.opacity(0.08))
        )
    }
}
