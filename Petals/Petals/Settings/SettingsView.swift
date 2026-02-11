import SwiftUI

struct SettingsView: View {
    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("eventTextSize") private var eventTextSize = AppSettings.eventTextSizeDefault
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault
    @AppStorage("hideSingleDayEvents") private var hideSingleDayEvents = false
    @AppStorage("obfuscateEventText") private var obfuscateText = false

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show Today Line", isOn: $showTodayLine)

                LabeledContent("Event Text Size") {
                    HStack {
                        Slider(value: $eventTextSize, in: 8...14, step: 1)
                        Text("\(Int(eventTextSize))pt")
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                }

                Stepper("Max Event Rows: \(maxEventRows)", value: $maxEventRows, in: 1...10)
            }

            Section("Events") {
                Toggle("Hide Single-Day Events", isOn: $hideSingleDayEvents)
                Toggle("Obfuscate Event Text", isOn: $obfuscateText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
    }
}
