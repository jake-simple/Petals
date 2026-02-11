import SwiftUI

struct InspectorPanel: View {
    @Bindable var item: CanvasItem
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section("Transform") {
                LabeledContent("Opacity") {
                    Slider(value: $item.opacity, in: 0.1...1.0, step: 0.05)
                }
                LabeledContent("Rotation") {
                    HStack {
                        Slider(value: $item.rotation, in: -180...180, step: 1)
                        Text("\(Int(item.rotation))°")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }

            // Type-specific
            switch CanvasItemType(rawValue: item.type) {
            case .text: textSection
            case .shape: shapeSection
            case .sticker: stickerSection
            default: EmptyView()
            }

            Section {
                Button("Delete Item", role: .destructive) { onDelete() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 260)
        .padding(.vertical, 8)
    }

    // MARK: - Text

    @ViewBuilder
    private var textSection: some View {
        Section("Text") {
            TextField("Content", text: Binding(
                get: { item.text ?? "" },
                set: { item.text = $0 }
            ), axis: .vertical)

            LabeledContent("Size") {
                Slider(value: Binding(
                    get: { item.fontSize ?? 16 },
                    set: { item.fontSize = $0 }
                ), in: 8...72, step: 1)
            }

            Toggle("Bold", isOn: Binding(
                get: { item.isBold ?? false },
                set: { item.isBold = $0 }
            ))

            Toggle("Italic", isOn: Binding(
                get: { item.isItalic ?? false },
                set: { item.isItalic = $0 }
            ))

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
                ), in: 0...10, step: 0.5)
            }
        }
    }

    // MARK: - Sticker

    @ViewBuilder
    private var stickerSection: some View {
        Section("Sticker") {
            TextField("SF Symbol Name", text: Binding(
                get: { item.stickerName ?? "" },
                set: { item.stickerName = $0 }
            ))
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
