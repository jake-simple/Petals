import SwiftUI

struct SettingsView: View {
    @AppStorage("showTodayLine") private var showTodayLine = AppSettings.showTodayLineDefault
    @AppStorage("maxEventRows") private var maxEventRows = AppSettings.maxEventRowsDefault

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show Today Line", isOn: $showTodayLine)
                Stepper("Max Event Rows: \(maxEventRows)", value: $maxEventRows, in: 1...10)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 180)
    }
}
