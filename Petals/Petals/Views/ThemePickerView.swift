import SwiftUI

struct ThemePickerView: View {
    let themes: [Theme]
    @Binding var selectedThemeID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.headline)

            ForEach(themes, id: \Theme.id) { theme in
                Button(action: { selectedThemeID = theme.id }) {
                    HStack(spacing: 10) {
                        // Color preview
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: theme.backgroundColor))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: theme.gridLineColor), lineWidth: 1)
                                Circle()
                                    .fill(Color(hex: theme.todayLineColor))
                                    .frame(width: 6, height: 6)
                            }
                            .frame(width: 36, height: 24)

                        Text(LocalizedStringKey(theme.name))
                            .foregroundStyle(.primary)

                        Spacer()

                        if theme.id == selectedThemeID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }

                        if theme.dark != nil {
                            Image(systemName: "circle.righthalf.filled")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}
