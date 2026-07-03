import SwiftUI
import EventKit

struct CalendarFilterView: View {
    @Bindable var eventManager: EventManager

    @State private var showingNewSetAlert = false
    @State private var newSetName = ""
    @State private var showingManage = false

    private var groupedCalendars: [(sourceTitle: String, sourceID: String, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: eventManager.calendars) {
            $0.source?.sourceIdentifier ?? "unknown"
        }
        return grouped
            .map { entry in
                let title = entry.value.first?.source?.title ?? String(localized: "Other")
                return (sourceTitle: title, sourceID: entry.key, calendars: entry.value)
            }
            .sorted { $0.sourceTitle.localizedCompare($1.sourceTitle) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            setPicker

            Divider()

            HStack {
                Text("Calendars")
                    .font(.headline)
                Spacer()
                Button("Select All", action: selectAll)
                    .disabled(allSelected)
                Button("Select None", action: selectNone)
                    .disabled(eventManager.selectedCalendarIDs.isEmpty)
            }
            .buttonStyle(.link)
            .font(.subheadline)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .alert("New Calendar Set", isPresented: $showingNewSetAlert) {
            TextField("Set name", text: $newSetName)
            Button("Save") {
                let name = newSetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                eventManager.createSet(name: name, calendarIDs: eventManager.selectedCalendarIDs)
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingManage) {
            CalendarSetManageView(eventManager: eventManager)
        }
    }

    private var setPicker: some View {
        Menu {
            ForEach(eventManager.calendarSets) { set in
                Button {
                    eventManager.selectSet(id: set.id)
                } label: {
                    if set.id == eventManager.activeCalendarSetID {
                        Label(set.name, systemImage: "checkmark")
                    } else {
                        Text(set.name)
                    }
                }
            }
            Divider()
            Button("Save Current as New Set…") {
                newSetName = ""
                showingNewSetAlert = true
            }
            Button("Manage Sets…") { showingManage = true }
        } label: {
            Label(eventManager.activeSet?.name ?? String(localized: "Default"),
                  systemImage: "rectangle.stack")
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allCalendarIDs: Set<String> {
        Set(eventManager.calendars.map(\.calendarIdentifier))
    }

    private var allSelected: Bool {
        !eventManager.calendars.isEmpty
            && allCalendarIDs.isSubset(of: eventManager.selectedCalendarIDs)
    }

    private func selectAll() {
        eventManager.setActiveSetCalendars(allCalendarIDs)
    }

    private func selectNone() {
        eventManager.setActiveSetCalendars([])
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding {
            eventManager.selectedCalendarIDs.contains(calendar.calendarIdentifier)
        } set: { isOn in
            eventManager.setCalendar(calendar.calendarIdentifier, enabled: isOn)
        }
    }
}
