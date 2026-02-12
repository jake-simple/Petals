import SwiftUI

struct ThemeColors: Codable, Sendable {
    var backgroundColor: String
    var gridLineColor: String
    var todayLineColor: String
    var monthLabelColor: String
    var dayLabelColor: String
    var weekendColor: String?
}

struct Theme: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var backgroundColor: String
    var gridLineColor: String
    var todayLineColor: String
    var monthLabelColor: String
    var dayLabelColor: String
    var weekendColor: String?
    var fontName: String?
    var dark: ThemeColors?

    func resolved(for colorScheme: ColorScheme) -> Theme {
        guard colorScheme == .dark, let dark else { return self }
        var copy = self
        copy.backgroundColor = dark.backgroundColor
        copy.gridLineColor = dark.gridLineColor
        copy.todayLineColor = dark.todayLineColor
        copy.monthLabelColor = dark.monthLabelColor
        copy.dayLabelColor = dark.dayLabelColor
        copy.weekendColor = dark.weekendColor
        return copy
    }
}

struct ThemeManager: Sendable {
    static let shared = ThemeManager()

    let themes: [Theme]

    init() {
        guard let url = Bundle.main.url(forResource: "Themes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Theme].self, from: data) else {
            self.themes = [Self.fallback]
            return
        }
        self.themes = decoded
    }

    func theme(for id: String) -> Theme {
        themes.first { $0.id == id } ?? Self.fallback
    }

    private static let fallback = Theme(
        id: "minimal-light",
        name: "Minimal",
        backgroundColor: "#FFFFFF",
        gridLineColor: "#E0E0E0",
        todayLineColor: "#FF6B35",
        monthLabelColor: "#333333",
        dayLabelColor: "#666666",
        weekendColor: "#F5F5F5"
    )
}

// MARK: - Hex Color

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double((rgbValue & 0x0000FF)) / 255.0
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
