import AppKit
import SwiftUI

/// Tracks the actual host window, including separately opened board windows.
@MainActor
final class WindowInputScope {
    weak var view: NSView?

    var isKeyWindow: Bool {
        guard let window = view?.window else { return false }
        return window.isKeyWindow && window.attachedSheet == nil
    }

    func contains(_ event: NSEvent) -> Bool {
        guard let view, let window = view.window,
              event.window === window, window.attachedSheet == nil else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point)
    }
}

struct WindowInputScopeReader: NSViewRepresentable {
    let scope: WindowInputScope

    func makeNSView(context: Context) -> NSView {
        let view = InputScopeView()
        scope.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scope.view = nsView
    }

    private final class InputScopeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
