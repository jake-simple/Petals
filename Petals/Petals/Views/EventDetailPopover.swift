import SwiftUI
import EventKit

private struct OnThisDayYearGroup: Identifiable {
    let year: Int
    let events: [EKEvent]
    var id: Int { year }
}

struct EventDetailPopover: View {
    let event: EKEvent
    let onEdit: () -> Void

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
                }
                .padding()
            }
        }
        .frame(width: 320).frame(minHeight: 240)
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

// MARK: - Day Events Popover

/// 날짜를 더블클릭하면 뜨는 "그날의 모든 일정" 목록. 일정을 누르면 편집 시트가 이 시트 위에 뜬다.
struct DayEventsPopover: View {
    let date: Date
    let eventManager: EventManager
    let onSaved: () -> Void

    @State private var onThisDayGroups: [OnThisDayYearGroup] = []
    @State private var editorContext: EventEditorContext?
    @Environment(\.dismiss) private var dismiss

    /// 해당 날짜에 걸치는 일정 — 종일 먼저, 그다음 시작 시각순. eventManager가 갱신되면 자동 반영.
    private var dayEvents: [EKEvent] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        return eventManager.events
            .filter { ev in
                guard let s = ev.startDate, let e = ev.endDate else { return false }
                return s < endOfDay && e > startOfDay
            }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return (a.startDate ?? .distantPast) < (b.startDate ?? .distantPast)
            }
    }

    var body: some View {
        listView
            .frame(minWidth: 420, minHeight: 600)
            .sheet(item: $editorContext) { ctx in
                EventEditorSheet(
                    eventManager: eventManager,
                    existingEvent: ctx.existingEvent,
                    initialStartDate: ctx.startDate,
                    initialEndDate: ctx.endDate,
                    onSave: onSaved
                )
            }
    }

    private var listView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    editorContext = EventEditorContext(startDate: date, endDate: date)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "새 이벤트"))
                if #available(macOS 26.0, *) {
                    Button(role: .close) { dismiss() }
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if dayEvents.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text(String(localized: "일정 없음"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, onThisDayGroups.isEmpty ? 60 : 24)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(dayEvents, id: \.eventIdentifier) { event in
                                Button {
                                    editorContext = EventEditorContext(existingEvent: event)
                                } label: {
                                    OnThisDayEventRow(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !onThisDayGroups.isEmpty {
                        onThisDaySection
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: date) {
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
                        Button {
                            editorContext = EventEditorContext(existingEvent: e)
                        } label: {
                            OnThisDayEventRow(event: e)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func yearsAgoLabel(_ year: Int) -> String {
        let currentYear = Calendar.current.component(.year, from: date)
        let diff = currentYear - year
        if diff == 1 {
            return String(localized: "1년 전, \(year)년")
        } else {
            return String(localized: "\(diff)년 전, \(year)년")
        }
    }

    private func loadOnThisDay() async {
        onThisDayGroups = []
        await eventManager.fetchOnThisDay(for: date) { batch in
            let newGroups = batch.map { OnThisDayYearGroup(year: $0.year, events: $0.events) }
            onThisDayGroups.append(contentsOf: newGroups)
            onThisDayGroups.sort { $0.year > $1.year }
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
