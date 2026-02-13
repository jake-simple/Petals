import SwiftUI
import AppKit

private class FontPanelTarget: NSObject {
    var currentFont: NSFont = .systemFont(ofSize: 16)
    var onChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let newFont = manager.convert(currentFont)
        currentFont = newFont
        onChange?(newFont)
    }
}

private let fontPanelTarget = FontPanelTarget()

struct InspectorPanel: View {
    @Bindable var item: CanvasItem
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section("Transform") {
                LabeledContent("Opacity") {
                    Slider(value: steppedBinding($item.opacity, step: 0.05), in: 0.1...1.0)
                }
                LabeledContent("Rotation") {
                    HStack {
                        Slider(value: steppedBinding($item.rotation, step: 1), in: -180...180)
                        Text("\(Int(item.rotation))°")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }

            // Type-specific
            switch CanvasItemType(rawValue: item.type) {
            case .image: imageSection
            case .text: textSection
            case .shape: shapeSection
            case .sticker: stickerSection
            default: EmptyView()
            }

        }
        .formStyle(.grouped)
        .frame(width: 260)
        .padding(.vertical, 8)
    }

    // MARK: - Image

    @ViewBuilder
    private var imageSection: some View {
        Section("Image") {
            LabeledContent("Corner Radius") {
                Slider(value: Binding(
                    get: { item.cornerRadius ?? 0 },
                    set: { item.cornerRadius = $0 }
                ), in: 0...100)
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private var textSection: some View {
        Section("Text") {
            TextField("Content", text: Binding(
                get: { item.text ?? "" },
                set: { item.text = $0 }
            ), axis: .vertical)

            LabeledContent("Font") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(currentFontLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Select Font…") { openFontPanel() }
                }
            }

            Picker("Alignment", selection: Binding(
                get: { item.textAlignment ?? "leading" },
                set: { item.textAlignment = $0 }
            )) {
                Text("Left").tag("leading")
                Text("Center").tag("center")
                Text("Right").tag("trailing")
            }
            .pickerStyle(.segmented)

            ColorPicker("Color", selection: hexColorBinding(\.textColor, default: "#333333"))
        }
    }

    private var currentFontLabel: String {
        let name = item.fontName.flatMap { NSFont(name: $0, size: 12)?.displayName } ?? "System"
        let size = Int(item.fontSize ?? 16)
        return "\(name), \(size)pt"
    }

    private func openFontPanel() {
        let currentNSFont: NSFont
        if let name = item.fontName, let font = NSFont(name: name, size: CGFloat(item.fontSize ?? 16)) {
            currentNSFont = font
        } else {
            currentNSFont = .systemFont(ofSize: CGFloat(item.fontSize ?? 16))
        }
        fontPanelTarget.currentFont = currentNSFont
        fontPanelTarget.onChange = { newFont in
            item.fontName = newFont.fontName
            item.fontSize = Double(newFont.pointSize)
            let traits = NSFontManager.shared.traits(of: newFont)
            item.isBold = traits.contains(.boldFontMask)
            item.isItalic = traits.contains(.italicFontMask)
        }
        NSFontManager.shared.target = fontPanelTarget
        NSFontManager.shared.action = #selector(FontPanelTarget.changeFont(_:))
        NSFontManager.shared.setSelectedFont(currentNSFont, isMultiple: false)
        NSFontPanel.shared.orderFront(nil)
    }

    // MARK: - Shape

    @ViewBuilder
    private var shapeSection: some View {
        Section("Shape") {
            Picker("Type", selection: Binding(
                get: { item.shapeType ?? "rectangle" },
                set: { item.shapeType = $0 }
            )) {
                Text("Rectangle").tag("rectangle")
                Text("Circle").tag("circle")
                Text("Line").tag("line")
            }

            ColorPicker("Fill", selection: hexColorBinding(\.fillColor, default: "#4A90D9"))
            ColorPicker("Stroke", selection: hexColorBinding(\.strokeColor, default: "#2C5F8A"))

            LabeledContent("Stroke Width") {
                Slider(value: Binding(
                    get: { item.strokeWidth ?? 1 },
                    set: { item.strokeWidth = $0 }
                ), in: 0...10)
            }
        }
    }

    // MARK: - Sticker

    @ViewBuilder
    private var stickerSection: some View {
        Section("Sticker") {
            ColorPicker("Color", selection: hexColorBinding(\.fillColor, default: "#000000"))
        }
    }

    // MARK: - Stepped Binding (tick mark 없이 step 동작)

    private func steppedBinding(_ binding: Binding<Double>, step: Double) -> Binding<Double> {
        Binding {
            binding.wrappedValue
        } set: { newValue in
            binding.wrappedValue = (newValue / step).rounded() * step
        }
    }

    // MARK: - Color Binding Helper

    private func hexColorBinding(_ keyPath: ReferenceWritableKeyPath<CanvasItem, String?>,
                                  default defaultHex: String) -> Binding<Color> {
        Binding {
            Color(hex: item[keyPath: keyPath] ?? defaultHex)
        } set: { newColor in
            item[keyPath: keyPath] = newColor.toHex()
        }
    }
}
