import SwiftUI

struct CaptureAnnotationTools: View {
    let state: CaptureEditorState
    @Environment(\.metrics) private var metrics
    @Environment(CaptureCoordinator.self) private var coordinator
    private var store: CaptureSettingsStore { coordinator.settings }

    var body: some View {
        VStack(spacing: metrics.spacing.xxs) {
            CaptureToolFlow(spacing: metrics.spacing.xxs) {
                ForEach(CaptureToolbarItem.all.filter { store.toolbarItems.contains($0) }, id: \.self) { item in
                    itemButton(item)
                }
                CaptureIconButton(title: "More Tools", symbol: "ellipsis",
                    selected: state.advancedTools || !store.toolbarItems.contains(.annotation(state.tool)),
                    hint: "Right-click any tool to keep it in the toolbar") {
                    state.advancedTools.toggle()
                }
                .contextMenu { customization }
                CaptureIconButton(title: "Undo", symbol: "arrow.uturn.backward", shortcut: "⌘Z") {
                    state.finishEditing(); state.undoEdit()
                }.disabled(!state.undo.canUndo)
                CaptureIconButton(title: "Redo", symbol: "arrow.uturn.forward", shortcut: "⇧⌘Z") {
                    state.finishEditing(); state.redoEdit()
                }.disabled(!state.undo.canRedo)
            }
            if state.advancedTools {
                CaptureToolFlow(spacing: metrics.spacing.xxs) {
                    ForEach(CaptureToolbarItem.all.filter { !store.toolbarItems.contains($0) }, id: \.self) { item in
                        itemButton(item)
                    }
                    Menu { customization } label: {
                        glyph("slider.horizontal.3")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Customize Toolbar").tooltip("Customize Toolbar")
                }
            }
        }
        .disabled(state.busy)
    }

    private var customization: some View {
        Group {
            ForEach(CaptureToolbarItem.all, id: \.self) { item in
                Toggle(item.title, isOn: Binding(
                    get: { store.toolbarItems.contains(item) },
                    set: { store.setToolbarItem(item, visible: $0) }))
                    .disabled(item == .annotation(.select))
            }
            Divider()
            Button("Reset Toolbar") { store.resetToolbar() }
        }
    }

    private func itemButton(_ item: CaptureToolbarItem) -> some View {
        action(item).contextMenu {
            if item != .annotation(.select) {
                Button(store.toolbarItems.contains(item) ? "Move to More Tools" : "Keep in Toolbar") {
                    store.setToolbarItem(item, visible: !store.toolbarItems.contains(item))
                }
            }
            Button("Reset Toolbar") { store.resetToolbar() }
        }
    }

    @ViewBuilder private func action(_ item: CaptureToolbarItem) -> some View {
        switch item {
        case let .annotation(tool):
            CaptureIconButton(title: tool.title, symbol: tool.symbol, shortcut: tool.key.uppercased(),
                selected: state.tool == tool, hint: tool == .select ? "Hold ⌥ to move without alignment" : "") {
                state.selectTool(tool)
            }
        case .pickColor:
            CaptureIconButton(title: item.title, symbol: item.symbol, selected: state.pickingColor) {
                state.finishEditing()
                state.pickingColor.toggle()
                state.notice = state.pickingColor ? "Click the image to pick a color. Esc to cancel." : nil
            }
        case .scanCodes:
            CaptureIconButton(title: item.title, symbol: item.symbol) { coordinator.scanCodes() }
        case .addImage:
            CaptureIconButton(title: item.title, symbol: item.symbol) { coordinator.addImage() }
        case .suggestCovers:
            Menu {
                ForEach(CaptureRedactionPolicy.allCases, id: \.self) { policy in
                    Button(policy.title) { coordinator.suggestRedactions(policy) }
                }
            } label: {
                glyph(item.symbol)
            }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(item.title).tooltip(item.title)
        case .adjustImage:
            CaptureIconButton(title: item.title, symbol: item.symbol, selected: state.imageAdjustments) {
                state.finishEditing()
                state.tool = .select
                state.selected = nil
                state.imageAdjustments.toggle()
                state.presentationControls = false
            }
        case .beautify:
            CaptureIconButton(title: item.title, symbol: item.symbol, selected: state.presentationControls) {
                state.finishEditing()
                state.tool = .select
                state.selected = nil
                state.imageAdjustments = false
                coordinator.expandCapture()
                state.presentationControls.toggle()
                if state.presentationControls, state.document.edit.presentation == nil {
                    state.setPresentation(.init())
                }
            }
        }
    }

    private func glyph(_ symbol: String) -> some View {
        SymbolImage(name: symbol, size: metrics.scaled(Theme.Size.captureGlyph))
            .frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
    }
}
