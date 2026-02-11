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
                Text(existingEvent == nil ? "New Event" : "Edit Event")
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

                Picker("Calendar", selection: $selectedCalendarID) {
                    ForEach(eventManager.calendars, id: \.calendarIdentifier) { cal in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: cal.cgColor))
                                .frame(width: 8, height: 8)
                            Text(cal.title)
                        }
                        .tag(cal.calendarIdentifier)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 450)
        .onAppear { populateFields() }
    }

    private var selectedCalendar: EKCalendar? {
        eventManager.calendars.first { $0.calendarIdentifier == selectedCalendarID }
    }

    private func populateFields() {
        if let event = existingEvent {
            title = event.title ?? ""
            startDate = event.startDate ?? Date()
            let rawEnd = event.endDate ?? Date()
            endDate = event.isAllDay
                ? Calendar.current.date(byAdding: .day, value: -1, to: rawEnd) ?? rawEnd
                : rawEnd
            isAllDay = event.isAllDay
            notes = event.notes ?? ""
            selectedCalendarID = event.calendar?.calendarIdentifier ?? ""
        } else {
            if let s = initialStartDate { startDate = s }
            if let e = initialEndDate { endDate = e }
            selectedCalendarID = eventManager.defaultCalendar?.calendarIdentifier ?? ""
        }
    }

    private func save() {
        guard let cal = selectedCalendar else {
            errorMessage = "Please select a calendar."
            return
        }

        do {
            if let event = existingEvent {
                event.title = title
                event.startDate = startDate
                event.endDate = isAllDay
                    ? Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                    : endDate
                event.isAllDay = isAllDay
                event.notes = notes.isEmpty ? nil : notes
                event.calendar = cal
                try eventManager.updateEvent(event)
            } else {
                let actualEnd = isAllDay
                    ? Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                    : endDate
                try eventManager.createEvent(
                    title: title,
                    startDate: startDate,
                    endDate: actualEnd,
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
