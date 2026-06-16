import Foundation
import SwiftData

/// Marketing screenshot capture mode.
///
/// Activated only when `PETALS_SHOT=1` is present in the process environment,
/// so normal app launches are completely unaffected. When active the app uses
/// an in-memory store, synthetic demo events, and an initial theme/zoom/mode
/// taken from the environment — producing deterministic, clean App Store shots.
enum ScreenshotConfig {
    private static let env = ProcessInfo.processInfo.environment

    static var isActive: Bool { env["PETALS_SHOT"] == "1" }

    /// Target App Store locale for demo content, e.g. "ko". Defaults to "en".
    static var lang: String {
        guard let value = env["PETALS_SHOT_LANG"], !value.isEmpty else { return "en" }
        return value
    }

    static var isKorean: Bool { lang == "ko" }

    /// Theme id override, e.g. "tokyo-night". Falls back to the document theme.
    static var theme: String? {
        guard let value = env["PETALS_SHOT_THEME"], !value.isEmpty else { return nil }
        return value
    }

    /// Months-per-page zoom: 12 (year), 3 (quarter), 1 (month).
    static var zoom: Int? {
        guard let raw = env["PETALS_SHOT_ZOOM"], let value = Int(raw),
              [1, 3, 12].contains(value) else { return nil }
        return value
    }

    /// Whether the app should open directly in whiteboard mode.
    static var startsInWhiteboard: Bool { env["PETALS_SHOT_MODE"] == "whiteboard" }

    /// Year shown in the calendar. Defaults to the current year.
    static var year: Int {
        if let raw = env["PETALS_SHOT_YEAR"], let value = Int(raw) { return value }
        return Calendar.current.component(.year, from: Date())
    }

    /// Seeds a few demo vision boards so the whiteboard sidebar looks populated.
    @MainActor
    static func seedDemoBoards(in context: ModelContext) {
        let names = isKorean
            ? ["2026 비전 보드", "여행 버킷리스트", "수채화 노트", "독서 기록"]
            : ["2026 Vision Board", "Travel Bucket List", "Watercolors", "Reading Log"]
        for (index, name) in names.enumerated() {
            context.insert(VisionBoard(name: name, sortIndex: index))
        }
        try? context.save()
    }
}
