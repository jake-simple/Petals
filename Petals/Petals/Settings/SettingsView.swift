import SwiftUI

struct SettingsView: View {
    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("dimPastDates") private var dimPastDates = AppSettings.dimPastDatesDefault
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault
    @AppStorage("eventFontSize") private var eventFontSize = AppSettings.eventFontSizeDefault

    @State private var selectedTab: SettingsTab = .display

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.icon)
                }
                .tag(SettingsTab.general)

            displayTab
                .tabItem {
                    Label(SettingsTab.display.title, systemImage: SettingsTab.display.icon)
                }
                .tag(SettingsTab.display)
        }
        .frame(width: 450, height: 300)
    }

    private var displayTab: some View {
        Form {
            Section(String(localized: "Display")) {
                Toggle(String(localized: "Show Today Line"), isOn: $showTodayLine)
                Toggle(String(localized: "Dim Past Dates"), isOn: $dimPastDates)
                Stepper(String(localized: "Max Event Rows: \(maxEventRows)"), value: $maxEventRows, in: 1...10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Event Font Size: \(Int(eventFontSize))pt"))
                    Slider(value: $eventFontSize, in: AppSettings.eventFontSizeRange, step: 1)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section(String(localized: "Feedback")) {
                Link(destination: URL(string: "mailto:jake@onessa.app")!) {
                    Label("jake@onessa.app", systemImage: "envelope")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private enum SettingsTab: CaseIterable {
    case display
    case general

    var title: String {
        switch self {
        case .display: return String(localized: "Display")
        case .general: return String(localized: "General")
        }
    }

    var icon: String {
        switch self {
        case .display: return "paintbrush"
        case .general: return "gearshape"
        }
    }
}
