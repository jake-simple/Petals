import SwiftUI
import EventKit

struct EventEditorSheet: View {
    let eventManager: EventManager
    let existingEvent: EKEvent?
    let initialStartDate: Date?
    let initialEndDate: Date?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isAllDay = true
    @State private var notes = ""
    @State private var selectedCalendarID: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text(existingEvent == nil ? LocalizedStringKey("New Event") : LocalizedStringKey("Edit Event"))
                    .font(.headline)
                Spacer()
                Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            Form {
                TextField("Title", text: $title)

                Toggle("All Day", isOn: $isAllDay)

                DatePicker("Start", selection: $startDate,
                           displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])

                DatePicker("End", selection: $endDate,
                           displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])

                if let event = existingEvent, event.hasRecurrenceRules, let rule = event.recurrenceRules?.first {
                    HStack {
                        Label("Repeat", systemImage: "repeat")
                        Spacer()
                        Text(recurrenceDescription(rule))
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Calendar", selection: $selectedCalendarID) {
                    let grouped = Dictionary(grouping: eventManager.calendars) { $0.source.title }
                    let sortedSources = grouped.keys.sorted()
                    ForEach(sortedSources, id: \.self) { source in
                        Section(source) {
                            ForEach(grouped[source]!, id: \.calendarIdentifier) { cal in
                                Label {
                                    Text(cal.title)
                                } icon: {
                                    Image(nsImage: colorDot(cal.cgColor))
                                }
                                .tag(cal.calendarIdentifier)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 480)
        .onAppear { populateFields() }
    }

    private var selectedCalendar: EKCalendar? {
        eventManager.calendars.first { $0.calendarIdentifier == selectedCalendarID }
    }

    private func populateFields() {
        if let event = existingEvent {
            title = event.title ?? ""
            startDate = event.startDate ?? Date()
            endDate = event.endDate ?? Date()
            isAllDay = event.isAllDay
            notes = event.notes ?? ""
            selectedCalendarID = event.calendar?.calendarIdentifier ?? ""
        } else {
            if let s = initialStartDate { startDate = s }
            if let e = initialEndDate { endDate = e }
            selectedCalendarID = eventManager.defaultCalendar?.calendarIdentifier ?? ""
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

    private func colorDot(_ cgColor: CGColor) -> NSImage {
        let size: CGFloat = 12
        let totalWidth: CGFloat = size + 4
        let image = NSImage(size: NSSize(width: totalWidth, height: size))
        image.lockFocus()
        NSColor(cgColor: cgColor)?.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func save() {
        guard let cal = selectedCalendar else {
            errorMessage = String(localized: "Please select a calendar.")
            return
        }

        do {
            if let event = existingEvent {
                event.title = title
                event.startDate = startDate
                event.endDate = endDate
                event.isAllDay = isAllDay
                event.notes = notes.isEmpty ? nil : notes
                event.calendar = cal
                try eventManager.updateEvent(event)
            } else {
                try eventManager.createEvent(
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    calendar: cal,
                    notes: notes.isEmpty ? nil : notes,
                    isAllDay: isAllDay
                )
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
