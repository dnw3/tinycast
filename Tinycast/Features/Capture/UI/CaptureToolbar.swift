import SwiftUI

struct CaptureIconButton: View {
    let title: String
    let symbol: String
    var shortcut = ""
    var selected = false
    var hint = ""
    let action: () -> Void
    @Environment(\.metrics) private var metrics
    @State private var hovered = false
    private var help: String {
        let title = shortcut.isEmpty ? title : "\(title)  \(shortcut)"
        return hint.isEmpty ? title : "\(title)\n\(hint)"
    }

    var body: some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: metrics.scaled(Theme.Size.captureGlyph))
                .frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
                .background(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.barControl))
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .onHover { hovered = $0 }
        .tooltip(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CaptureToolProperties: View {
    @Bindable var state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    private var tool: CaptureAnnotation.Tool {
        state.document.edit.annotations.first(where: { $0.id == state.selected })?.tool ?? state.tool
    }

    var body: some View {
        if let image = state.selectedImage {
            CaptureImageLayerControls(state: state, image: image)
        } else if tool == .emoji {
            CaptureEmojiControls(state: state)
        } else if tool == .magnifier {
            Picker("Magnification", selection: Binding(get: { state.magnification }, set: {
                state.magnification = $0
                state.updateSelectedStyle()
            })) {
                ForEach([2.0, 4, 8], id: \.self) { Text("\(Int($0))×").tag($0) }
            }.fixedSize().disabled(state.busy)
        } else if tool == .blur {
            Picker("Blur", selection: Binding(get: { state.strokeWidth }, set: {
                state.strokeWidth = $0; state.updateSelectedStyle()
            })) {
                Text("Light").tag(4.0)
                Text("Medium").tag(8.0)
                Text("Strong").tag(12.0)
            }
            .fixedSize().disabled(state.busy)
        } else if ![.select, .crop, .pixelate, .cover, .spotlight, .erase].contains(tool) {
            CaptureToolFlow(spacing: metrics.spacing.md) {
                ForEach(CaptureAnnotation.Ink.allCases, id: \.self) { ink in
                    let rgba = ink.rgba
                    Button {
                        state.ink = ink
                        state.color = nil
                        state.updateSelectedStyle()
                    } label: {
                        Circle().fill(Color(red: rgba[0], green: rgba[1], blue: rgba[2]))
                            .frame(
                                width: metrics.scaled(Theme.Size.captureGlyph),
                                height: metrics.scaled(Theme.Size.captureGlyph))
                            .padding(metrics.spacing.xs)
                            .overlay(Circle().strokeBorder(
                                state.ink == ink && state.color == nil ? Theme.Colors.textPrimary : .clear))
                    }
                    .buttonStyle(.borderless).focusable(false)
                    .accessibilityLabel(ink.rawValue.capitalized)
                    .accessibilityAddTraits(state.ink == ink && state.color == nil ? .isSelected : [])
                }
                if state.color != nil { CaptureColorField(state: state) }
                if tool == .text {
                    Picker("Font", selection: Binding(get: { state.font }, set: {
                        state.font = $0; state.updateSelectedStyle()
                    })) {
                        ForEach(CaptureAnnotation.Font.allCases, id: \.self) { font in Text(font.title).tag(font) }
                    }.fixedSize()
                    HStack(spacing: metrics.spacing.xxs) {
                        TextField("Size", value: $state.fontSize, format: .number)
                            .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                            .onSubmit {
                                state.fontSize = state.fontSize.isFinite ? min(768, max(6, state.fontSize)) : 24
                                state.updateSelectedStyle()
                            }.accessibilityLabel("Font Size")
                        Text("pt")
                    }.fixedSize().tooltip("Font Size")
                } else {
                    Picker("Stroke", selection: Binding(get: { state.strokeWidth }, set: {
                        state.strokeWidth = $0; state.updateSelectedStyle()
                    })) {
                        Text("Fine").tag(2.0)
                        Text("Medium").tag(4.0)
                        Text("Bold").tag(8.0)
                    }.fixedSize()
                }
                if tool == .rectangle || tool == .ellipse {
                    Toggle("Fill", isOn: Binding(get: { state.filled }, set: {
                        state.filled = $0; state.updateSelectedStyle()
                    })).toggleStyle(.checkbox)
                }
                HStack(spacing: metrics.spacing.xxs) {
                    TextField("Rotation", value: $state.rotation, format: .number)
                        .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                        .onSubmit {
                            state.rotation = state.rotation.isFinite ? min(180, max(-180, state.rotation)) : 0
                            state.updateSelectedStyle()
                        }.accessibilityLabel("Rotation in Degrees")
                    Text("°")
                }.fixedSize().tooltip("Rotation")
            }
            .disabled(state.busy)
        }
    }
}

struct CaptureOutputTools: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    var inline = false

    var body: some View {
        CaptureIconButton(title: "Copy", symbol: "doc.on.doc", shortcut: "⌘C / Return", selected: true) {
            coordinator.copy()
        }
        CaptureIconButton(title: "Save", symbol: "square.and.arrow.down", shortcut: "⌘S") { coordinator.save() }
        CaptureIconButton(title: "Pin", symbol: "pin") { coordinator.pin() }
        CaptureIconButton(title: "Extract Text", symbol: "text.viewfinder") { coordinator.recognize(translate: false) }
        Menu {
            Button("Text Panel") { coordinator.recognize(translate: true) }
            Button("Translate in Image…") { coordinator.prepareImageTranslation() }
        } label: {
            SymbolImage(name: "translate", size: coordinator.metrics.scaled(Theme.Size.captureGlyph))
                .frame(width: coordinator.metrics.scaled(Theme.Size.captureTool),
                    height: coordinator.metrics.scaled(Theme.Size.captureTool))
        } primaryAction: {
            coordinator.recognize(translate: true)
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Translate").tooltip("Translate")
        CaptureIconButton(title: "Share", symbol: "square.and.arrow.up") { coordinator.shareImage() }
        if inline {
            CaptureIconButton(title: "Expand Editor", symbol: "arrow.up.left.and.arrow.down.right") {
                coordinator.expandCapture()
            }
        }
    }
}
