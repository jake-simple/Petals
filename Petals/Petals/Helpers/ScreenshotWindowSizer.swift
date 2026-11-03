import SwiftUI
import AppKit

/// In screenshot mode, pins the window to a fixed on-screen size and disables
/// state restoration — otherwise a stale (possibly off-screen) saved frame can
/// hijack the capture. Inert during normal launches.
struct ScreenshotWindowSizer: NSViewRepresentable {
    /// 16:10 — matches the App Store poster device frame aspect ratio.
    static let aspectRatio: CGFloat = 16.0 / 10.0

    /// Target on-screen width (points). The poster shows the captured window at
    /// ~1150px, so a compact window maps roughly 1:1 onto the poster instead of
    /// being downscaled — keeping event text legible. Sizing to the whole screen
    /// (on a large display) shrinks that text below readability in the poster.
    static var targetWidth: CGFloat {
        guard ScreenshotConfig.isActive,
              let raw = ProcessInfo.processInfo.environment["PETALS_SHOT_WIDTH"],
              let width = Double(raw) else { return 1600 }
        return CGFloat(min(1600, max(900, width)))
    }

    /// Compact 16:10 window: `targetWidth`, clamped to the screen's visible area.
    static func contentSize(for screen: NSScreen) -> NSSize {
        let visible = screen.visibleFrame
        var width = min(targetWidth, (visible.width * 0.96).rounded())
        var height = (width / aspectRatio).rounded()
        let maxHeight = (visible.height * 0.96).rounded()
        if height > maxHeight {
            height = maxHeight
            width = (height * aspectRatio).rounded()
        }
        return NSSize(width: width, height: height)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView()
        view.onAttachment = { [weak view] in
            if let view { applyIfNeeded(view) }
        }
        applyIfNeeded(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyIfNeeded(nsView)
    }

    private func applyIfNeeded(_ view: NSView) {
        guard ScreenshotConfig.isActive else { return }
        DispatchQueue.main.async {
            guard let view = view as? WindowAttachmentView, let window = view.window,
                  view.sizedWindow !== window else { return }
            view.sizedWindow = window
            window.isRestorable = false
            window.setFrameAutosaveName("")
            window.styleMask.remove(.fullScreen)
            guard let screen = window.screen ?? NSScreen.main else { return }
            let size = Self.contentSize(for: screen)
            window.setContentSize(size)
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            )
            window.setFrameOrigin(origin)
        }
    }
}

private final class WindowAttachmentView: NSView {
    weak var sizedWindow: NSWindow?
    var onAttachment: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onAttachment?() }
    }
}
