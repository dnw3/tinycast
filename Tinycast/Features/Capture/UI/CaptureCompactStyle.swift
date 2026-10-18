import SwiftUI

struct CaptureCompactStyle: View {
    let state: CaptureEditorState
    @Environment(CaptureCoordinator.self) private var coordinator

    private var tool: CaptureAnnotation.Tool {
        state.document.edit.annotations.first { $0.id == state.selected }?.tool ?? state.tool
    }

    var body: some View {
        Menu {
            if ![.select, .crop, .pixelate, .cover, .spotlight, .erase, .magnifier, .blur, .emoji].contains(
                tool)
            {
                Menu("Color") {
                    ForEach(CaptureAnnotation.Ink.allCases, id: \.self) { ink in
                        Button {
                            state.ink = ink
                            state.color = nil
                            if tool == .text {
                                state.changeText(.color(state.currentTextStyle.color))
                            } else {
                                state.updateSelectedStyle()
                            }
                        } label: {
                            Label(
                                LocalizedStringKey(ink.title),
                                systemImage: state.ink == ink && state.color == nil ? "checkmark" : "circle")
                        }
                    }
                }
                if tool == .text {
                    Menu("Font") {
                        ForEach(CaptureAnnotation.Font.allCases, id: \.self) { font in
                            Button(LocalizedStringKey(font.title)) { state.changeText(.font(font)) }
                        }
                    }
                    Menu("Font Size") {
                        ForEach([16.0, 24, 32, 48, 64], id: \.self) { size in
                            Button("\(Int(size)) pt") { state.changeText(.size(size)) }
                        }
                    }
                    CaptureTextStyleControls(state: state)
                } else {
                    Menu("Stroke") {
                        Button("Fine") { setStroke(2) }
                        Button("Medium") { setStroke(4) }
                        Button("Bold") { setStroke(8) }
                    }
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
                    }
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
                        }
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
                    }
                    Toggle(
                        "Reverse",
                        isOn: Binding(
                            get: { state.reversed },
                            set: {
                                state.reversed = $0; state.updateSelectedStyle()
                            }))
                }
                if tool == .number {
                    Picker(
                        "Number Format",
                        selection: Binding(
                            get: { state.numberStyle },
                            set: {
                                state.numberStyle = $0; state.updateSelectedStyle()
                            })
                    ) {
                        ForEach(CaptureNumberFormat.Style.allCases, id: \.self) {
                            Text(LocalizedStringKey($0.title)).tag($0)
                        }
                    }
                    Menu("Next Number") {
                        ForEach([1, 5, 10, 25, 50, 100], id: \.self) { value in
                            Button("\(value)") { state.nextNumber = value }
                        }
                        Button("Custom Value in Editor…") { coordinator.expandCapture() }
                    }
                    Toggle(
                        "Leader",
                        isOn: Binding(
                            get: { state.numberLeader },
                            set: {
                                state.numberLeader = $0; state.updateSelectedStyle()
                            }))
                }
                if tool == .pen {
                    Toggle(
                        "Smooth",
                        isOn: Binding(
                            get: { state.smoothPen },
                            set: {
                                state.smoothPen = $0; state.updateSelectedStyle()
                            }))
                }
                if tool == .highlighter { CaptureHighlightControls(state: state) }
            } else if tool == .blur {
                Menu("Blur") {
                    Button("Soft") { setStroke(4) }
                    Button("Medium") { setStroke(8) }
                    Button("Strong") { setStroke(12) }
                }
            } else if tool == .magnifier {
                ForEach([2.0, 4, 8], id: \.self) { scale in
                    Button("\(Int(scale))×") {
                        state.magnification = scale; state.updateSelectedStyle()
                    }
                }
            }
            Button("More Style Options in Editor…") { coordinator.expandCapture() }
        } label: {
            CaptureToolbarGlyph(symbol: "paintpalette")
        }
        .menuStyle(CaptureToolbarMenuStyle()).fixedSize().accessibilityLabel(String(localized: "Style"))
        .tooltip(String(localized: "Style"))
        .disabled(state.busy)
    }

    private func setStroke(_ width: Double) {
        state.strokeWidth = width
        state.updateSelectedStyle()
    }
}
