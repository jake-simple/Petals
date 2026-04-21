import SwiftUI
import SwiftData

extension Notification.Name {
    static let performCopy = Notification.Name("performCopy")
    static let performPaste = Notification.Name("performPaste")
}

@Observable
@MainActor
final class ClipboardManager {
    var snapshot: CanvasItemSnapshot?
    var showCopyToast = false
    private var toastTask: Task<Void, Never>?

    func performCopy(snapshot: CanvasItemSnapshot) {
        self.snapshot = snapshot
        triggerCopyToast()
    }

    func triggerCopyToast() {
        toastTask?.cancel()
        showCopyToast = true
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            withAnimation { self.showCopyToast = false }
        }
    }
}

// MARK: - Canvas Key Commands

/// Cmd+C/V(메뉴 커맨드), Delete/Escape(NSEvent 모니터) 처리를 통합하는 ViewModifier.
struct CanvasKeyCommands: ViewModifier {
    @Binding var selectedItemIDs: Set<PersistentIdentifier>
    @Binding var showInspector: Bool
    var onDelete: () -> Void
    var onCopy: () -> Void
    var onPaste: () -> Void

    @State private var keyMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .performCopy)) { _ in
                onCopy()
            }
            .onReceive(NotificationCenter.default.publisher(for: .performPaste)) { _ in
                onPaste()
            }
            .onAppear { installKeyMonitor() }
            .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 51 || event.keyCode == 117 {
                guard !selectedItemIDs.isEmpty else { return event }
                onDelete()
                return nil
            }
            if event.keyCode == 53 {
                selectedItemIDs.removeAll()
                showInspector = false
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
