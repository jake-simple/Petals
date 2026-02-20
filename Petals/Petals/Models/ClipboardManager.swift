import SwiftUI

@Observable
final class ClipboardManager {
    var snapshot: CanvasItemSnapshot?
    var showCopyToast = false
    private var toastWorkItem: DispatchWorkItem?

    func triggerCopyToast() {
        toastWorkItem?.cancel()
        showCopyToast = true
        let work = DispatchWorkItem { [weak self] in
            withAnimation { self?.showCopyToast = false }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
