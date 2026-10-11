import SwiftUI

struct CaptureIconButton: View {
    let title: String
    let symbol: String
    var shortcut = ""
    var selected = false
    var hint = ""
    let action: () -> Void
    private var help: String {
        let name = Bundle.main.localizedString(forKey: title, value: nil, table: nil)
        let title = shortcut.isEmpty ? name : "\(name)  \(shortcut)"
        return hint.isEmpty ? title : String(localized: "\(title)\n\(hint)")
    }

    var body: some View {
        Button(action: action) {
            CaptureToolbarGlyph(symbol: symbol)
        }
        .buttonStyle(CaptureToolbarButtonStyle(selected: selected))
        .focusable(false)
        .tooltip(help)
        .accessibilityLabel(Bundle.main.localizedString(forKey: title, value: nil, table: nil))
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
            Picker(
                "Magnification",
                selection: Binding(
                    get: { state.magnification },
                    set: {
                        state.magnification = $0
                        state.updateSelectedStyle()
                    })
            ) {
                ForEach([2.0, 4, 8], id: \.self) { Text("\(Int($0))×").tag($0) }
            }.fixedSize().disabled(state.busy)
        } else if tool == .blur {
            Picker(
                "Blur",
                selection: Binding(
                    get: { state.strokeWidth },
                    set: {
                        state.strokeWidth = $0; state.updateSelectedStyle()
                    })
            ) {
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
                        if tool == .text {
                            state.changeText(.color(state.currentTextStyle.color))
                        } else {
                            state.updateSelectedStyle()
                        }
                    } label: {
                        Circle().fill(Color(red: rgba[0], green: rgba[1], blue: rgba[2]))
                            .frame(
                                width: metrics.scaled(Theme.Size.captureGlyph),
                                height: metrics.scaled(Theme.Size.captureGlyph)
                            )
                            .padding(metrics.spacing.xs)
                            .overlay(
                                Circle().strokeBorder(
                                    state.ink == ink && state.color == nil ? Theme.Colors.textPrimary : .clear
                                ))
                    }
                    .buttonStyle(.borderless).focusable(false)
                    .accessibilityLabel(ink.rawValue.capitalized)
                    .accessibilityAddTraits(state.ink == ink && state.color == nil ? .isSelected : [])
                }
                if state.color != nil { CaptureColorField(state: state) }
                if tool == .text {
                    Picker(
                        "Font",
                        selection: Binding(
                            get: { state.font },
                            set: {
                                state.changeText(.font($0))
                            })
                    ) {
                        ForEach(CaptureAnnotation.Font.allCases, id: \.self) { font in
                            Text(LocalizedStringKey(font.title)).tag(font)
                        }
                    }.fixedSize()
                    HStack(spacing: metrics.spacing.xxs) {
                        TextField("Size", value: $state.fontSize, format: .number)
                            .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                            .onSubmit {
                                state.fontSize =
                                    state.fontSize.isFinite ? min(768, max(6, state.fontSize)) : 24
                                state.changeText(.size(state.fontSize))
                            }.accessibilityLabel(String(localized: "Font Size"))
                        Text("pt")
                    }.fixedSize().tooltip(String(localized: "Font Size"))
                    Menu("Text Style") { CaptureTextStyleControls(state: state) }
                        .fixedSize().focusable(false)
                } else {
                    Picker(
                        "Stroke",
                        selection: Binding(
                            get: { state.strokeWidth },
                            set: {
                                state.strokeWidth = $0; state.updateSelectedStyle()
                            })
                    ) {
                        Text("Fine").tag(2.0)
                        Text("Medium").tag(4.0)
                        Text("Bold").tag(8.0)
                    }.fixedSize()
                }
                if tool == .rectangle || tool == .ellipse {
                    Picker(
                        "Shape",
                        selection: Binding(
                            get: { state.shapeStyle },
                            set: {
                                state.shapeStyle = $0; state.updateSelectedStyle()
                            })
                    ) {
                        ForEach(CaptureAnnotation.ShapeStyle.allCases, id: \.self) {
                            Text(LocalizedStringKey($0.title)).tag($0)
                        }
                    }.fixedSize()
                    if tool == .rectangle {
                        Picker(
                            "Corners",
                            selection: Binding(
                                get: { state.cornerRadius },
                                set: {
                                    state.cornerRadius = $0; state.updateSelectedStyle()
                                })
                        ) {
                            Text("Square").tag(0.0)
                            Text("Rounded").tag(12.0)
                            Text("Round").tag(32.0)
                        }.fixedSize()
                    }
                }
                if tool == .arrow || tool == .curvedArrow {
                    Picker(
                        "Arrow",
                        selection: Binding(
                            get: { state.arrowStyle },
                            set: {
                                state.arrowStyle = $0; state.updateSelectedStyle()
                            })
                    ) {
                        ForEach(CaptureAnnotation.ArrowStyle.allCases, id: \.self) {
                            Text(LocalizedStringKey($0.title)).tag($0)
                        }
                    }.fixedSize()
                    Toggle(
                        "Reverse",
                        isOn: Binding(
                            get: { state.reversed },
                            set: {
                                state.reversed = $0; state.updateSelectedStyle()
                            })
                    ).toggleStyle(.checkbox)
                }
                if tool == .number { CaptureNumberControls(state: state) }
                if tool == .highlighter { CaptureHighlightControls(state: state) }
                if tool == .pen {
                    Toggle(
                        "Smooth",
                        isOn: Binding(
                            get: { state.smoothPen },
                            set: {
                                state.smoothPen = $0; state.updateSelectedStyle()
                            })
                    ).toggleStyle(.checkbox)
                }
                HStack(spacing: metrics.spacing.xxs) {
                    TextField("Rotation", value: $state.rotation, format: .number)
                        .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                        .onSubmit {
                            state.rotation = state.rotation.isFinite ? min(180, max(-180, state.rotation)) : 0
                            state.updateSelectedStyle()
                        }.accessibilityLabel(String(localized: "Rotation in Degrees"))
                    Text("°")
                }.fixedSize().tooltip(String(localized: "Rotation"))
            }
            .disabled(state.busy)
        }
    }
}

struct CaptureOutputTools: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    var inline = false
    var maximumItems = CaptureToolbarAction.allCases.count

    private var actions: [CaptureToolbarAction] {
        coordinator.settings.toolbarConfiguration.orderedItems(actions: true).compactMap { item in
            guard case let .action(action) = item, inline || !action.needsSelection else { return nil }
            return action
        }
    }

    var body: some View {
        ForEach(Array(actions.prefix(maximumItems)), id: \.self) { action in
            CaptureActionButton(action: action)
        }
        if actions.count > maximumItems {
            Menu {
                ForEach(Array(actions.dropFirst(maximumItems)), id: \.self) { action in
                    CaptureActionButton(action: action, inMenu: true)
                }
            } label: {
                CaptureToolbarGlyph(symbol: "ellipsis")
            }
            .menuStyle(CaptureToolbarMenuStyle()).accessibilityLabel(String(localized: "More Actions"))
            .tooltip(String(localized: "More Actions"))
        }
        if inline {
            CaptureIconButton(
                title: String(localized: "Expand Editor"), symbol: "arrow.up.left.and.arrow.down.right"
            ) {
                coordinator.expandCapture()
            }
        }
    }
}
