import SwiftUI

struct CaptureIconButton: View {
    let title: String
    let symbol: String
    var shortcut = ""
    var selected = false
    var hint = ""
    var tint: Color?
    let action: () -> Void
    private var help: String {
        let name = Bundle.main.localizedString(forKey: title, value: nil, table: nil)
        let title = shortcut.isEmpty ? name : "\(name)  \(shortcut)"
        return hint.isEmpty ? title : String(localized: "\(title)\n\(hint)")
    }

    var body: some View {
        Button(action: action) {
            CaptureToolbarGlyph(symbol: symbol).foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
        }
        .buttonStyle(CaptureToolbarButtonStyle(selected: selected))
        .focusable(false)
        .tooltip(help)
        .accessibilityLabel(Bundle.main.localizedString(forKey: title, value: nil, table: nil))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A setting shown by its current value, like `1×` or `MP4`, named only in its tooltip.
struct CaptureValueMenu<Content: View>: View {
    let title: String
    var symbol: String?
    let value: String
    @ViewBuilder let content: () -> Content
    @Environment(\.metrics) private var metrics

    var body: some View {
        Menu(content: content) {
            HStack(spacing: metrics.spacing.xxs) {
                if let symbol { CaptureToolbarGlyph(symbol: symbol) }
                Text(value).monospacedDigit()
                Image(systemName: "chevron.down").font(metrics.typography.disclosure)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(metrics.typography.bar)
        }
        .menuStyle(CaptureToolbarMenuStyle(fitsContent: true)).fixedSize()
        .tooltip(title).accessibilityLabel(title).accessibilityValue(value)
    }
}

/// A `CaptureValueMenu` over a fixed list, checking the current choice.
struct CapturePickerMenu<Value: Hashable>: View {
    let title: String
    var symbol: String?
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        CaptureValueMenu(
            title: title, symbol: symbol, value: options.first { $0.value == selection }?.label ?? ""
        ) {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].label).tag(options[$0].value) }
            }
            .pickerStyle(.inline).labelsHidden()
        }
    }
}

struct CaptureToolProperties: View {
    @Bindable var state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    private func localized(_ title: String) -> String {
        Bundle.main.localizedString(forKey: title, value: nil, table: nil)
    }

    private var tool: CaptureAnnotation.Tool {
        state.document.edit.annotations.first(where: { $0.id == state.selected })?.tool ?? state.tool
    }

    var body: some View {
        if let image = state.selectedImage {
            CaptureImageLayerControls(state: state, image: image)
        } else if tool == .emoji {
            CaptureEmojiControls(state: state)
        } else if tool == .magnifier {
            CapturePickerMenu(
                title: String(localized: "Magnification"), symbol: "plus.magnifyingglass",
                options: [2.0, 4, 8].map { ($0, "\(Int($0))×") },
                selection: Binding(
                    get: { state.magnification },
                    set: {
                        state.magnification = $0
                        state.updateSelectedStyle()
                    })
            ).disabled(state.busy)
        } else if tool == .blur {
            CapturePickerMenu(
                title: String(localized: "Blur"), symbol: "drop",
                options: [
                    (4.0, String(localized: "Soft")), (8.0, String(localized: "Medium")),
                    (12.0, String(localized: "Strong"))
                ],
                selection: Binding(
                    get: { state.strokeWidth },
                    set: {
                        state.strokeWidth = $0; state.updateSelectedStyle()
                    })
            ).disabled(state.busy)
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
                    .accessibilityLabel(Text(LocalizedStringKey(ink.title)))
                    .accessibilityAddTraits(state.ink == ink && state.color == nil ? .isSelected : [])
                }
                if state.color != nil { CaptureColorField(state: state) }
                if tool == .text {
                    CapturePickerMenu(
                        title: String(localized: "Font"), symbol: "textformat",
                        options: CaptureAnnotation.Font.allCases.map { ($0, localized($0.title)) },
                        selection: Binding(get: { state.font }, set: { state.changeText(.font($0)) }))
                    HStack(spacing: metrics.spacing.xxs) {
                        TextField("Size", value: $state.fontSize, format: .number)
                            .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                            .captureField(metrics)
                            .onSubmit {
                                state.fontSize =
                                    state.fontSize.isFinite ? min(768, max(6, state.fontSize)) : 24
                                state.changeText(.size(state.fontSize))
                            }.accessibilityLabel(String(localized: "Font Size"))
                        Text("pt")
                    }.fixedSize().tooltip(String(localized: "Font Size"))
                    Menu { CaptureTextStyleControls(state: state) } label: {
                        CaptureToolbarGlyph(symbol: "bold.italic.underline")
                    }
                    .menuStyle(CaptureToolbarMenuStyle()).fixedSize().focusable(false)
                    .tooltip(String(localized: "Text Style")).accessibilityLabel(String(localized: "Text Style"))
                } else {
                    CapturePickerMenu(
                        title: String(localized: "Stroke"), symbol: "lineweight",
                        options: [
                            (2.0, String(localized: "Fine")), (4.0, String(localized: "Medium")),
                            (8.0, String(localized: "Bold"))
                        ],
                        selection: Binding(
                            get: { state.strokeWidth },
                            set: {
                                state.strokeWidth = $0; state.updateSelectedStyle()
                            }))
                }
                if tool == .rectangle || tool == .ellipse {
                    CapturePickerMenu(
                        title: String(localized: "Shape"), symbol: "square.on.circle",
                        options: CaptureAnnotation.ShapeStyle.allCases.map { ($0, localized($0.title)) },
                        selection: Binding(
                            get: { state.shapeStyle },
                            set: {
                                state.shapeStyle = $0; state.updateSelectedStyle()
                            }))
                    if tool == .rectangle {
                        CapturePickerMenu(
                            title: String(localized: "Corners"), symbol: "app.dashed",
                            options: [
                                (0.0, String(localized: "Square")), (12.0, String(localized: "Rounded")),
                                (32.0, String(localized: "Round"))
                            ],
                            selection: Binding(
                                get: { state.cornerRadius },
                                set: {
                                    state.cornerRadius = $0; state.updateSelectedStyle()
                                }))
                    }
                }
                if tool == .arrow || tool == .curvedArrow {
                    CapturePickerMenu(
                        title: String(localized: "Arrow"), symbol: "arrow.up.right",
                        options: CaptureAnnotation.ArrowStyle.allCases.map { ($0, localized($0.title)) },
                        selection: Binding(
                            get: { state.arrowStyle },
                            set: {
                                state.arrowStyle = $0; state.updateSelectedStyle()
                            }))
                    CaptureIconButton(
                        title: String(localized: "Reverse"), symbol: "arrow.left.arrow.right", selected: state.reversed
                    ) {
                        state.reversed.toggle(); state.updateSelectedStyle()
                    }
                }
                if tool == .number { CaptureNumberControls(state: state) }
                if tool == .highlighter { CaptureHighlightControls(state: state) }
                if tool == .pen {
                    CaptureIconButton(
                        title: String(localized: "Smooth"), symbol: "scribble.variable", selected: state.smoothPen
                    ) {
                        state.smoothPen.toggle(); state.updateSelectedStyle()
                    }
                }
                HStack(spacing: metrics.spacing.xxs) {
                    TextField("Rotation", value: $state.rotation, format: .number)
                        .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                        .captureField(metrics)
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
