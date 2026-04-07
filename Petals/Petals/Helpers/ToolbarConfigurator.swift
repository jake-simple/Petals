import AppKit
import SwiftUI

/// 툴바 우클릭 시 나타나는 "아이콘만 / 아이콘 및 텍스트" 메뉴를 제거합니다.
struct ToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let toolbar = view.window?.toolbar else { return }
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
