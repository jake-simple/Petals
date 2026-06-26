import SwiftUI
import SwiftData
import AppKit

extension Notification.Name {
    static let performCopy = Notification.Name("performCopy")
    static let performPaste = Notification.Name("performPaste")
}

@Observable
@MainActor
final class ClipboardManager {
    /// 앱 내부에서 복사한 캔버스 아이템들 (여러 개 지원)
    var snapshots: [CanvasItemSnapshot] = []
    var showCopyToast = false
    private var toastTask: Task<Void, Never>?

    /// 내부 복사 시점의 시스템 페이스트보드 changeCount.
    /// 이후 시스템 changeCount가 달라졌으면 외부에서 더 최근에 복사한 것으로 본다.
    private var copyChangeCount: Int = -1

    func performCopy(snapshots: [CanvasItemSnapshot]) {
        guard !snapshots.isEmpty else { return }
        self.snapshots = snapshots
        self.copyChangeCount = NSPasteboard.general.changeCount
        triggerCopyToast()
    }

    // MARK: - System Pasteboard

    /// 시스템 클립보드에 캔버스로 붙여넣을 수 있는 이미지/텍스트가 있는지
    var systemPasteboardHasContent: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
            || systemString() != nil
    }

    /// 붙여넣기 가능한 콘텐츠(내부 스냅샷 또는 시스템 클립보드)가 있는지
    var hasPasteableContent: Bool {
        !snapshots.isEmpty || systemPasteboardHasContent
    }

    /// 내부 복사 이후 외부에서 더 최근에 복사가 일어났으면 시스템 클립보드를 우선한다.
    var shouldUseSystemPasteboard: Bool {
        guard systemPasteboardHasContent else { return false }
        if snapshots.isEmpty { return true }
        return NSPasteboard.general.changeCount != copyChangeCount
    }

    func systemImage() -> NSImage? {
        NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
    }

    func systemString() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return nil }
        return s
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
                // 텍스트 편집 중이면 글자 삭제가 우선되도록 이벤트를 그대로 통과시킨다.
                if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
                    return event
                }
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
