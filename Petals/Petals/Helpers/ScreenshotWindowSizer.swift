import SwiftUI
import AppKit

/// In screenshot mode, pins the window to a fixed on-screen size and disables
/// state restoration — otherwise a stale (possibly off-screen) saved frame can
/// hijack the capture. Inert during normal launches.
struct ScreenshotWindowSizer: NSViewRepresentable {
    static let contentSize = NSSize(width: 1280, height: 800)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        applyIfNeeded(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyIfNeeded(nsView)
    }

    private func applyIfNeeded(_ view: NSView) {
        guard ScreenshotConfig.isActive else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isRestorable = false
            window.setFrameAutosaveName("")
            window.styleMask.remove(.fullScreen)
            window.setContentSize(Self.contentSize)
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                let origin = NSPoint(
                    x: visible.midX - window.frame.width / 2,
                    y: visible.midY - window.frame.height / 2
                )
                window.setFrameOrigin(origin)
            }
        }
    }
}
