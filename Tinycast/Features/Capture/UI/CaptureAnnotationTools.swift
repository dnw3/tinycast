import SwiftUI

struct CaptureAnnotationTools: View {
    let state: CaptureEditorState
    var maximumItems = CaptureToolbarItem.all.count
    @Environment(\.metrics) private var metrics
    @Environment(CaptureCoordinator.self) private var coordinator
    private var store: CaptureSettingsStore { coordinator.settings }

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            ForEach(
                Array(store.toolbarConfiguration.orderedItems(actions: false).prefix(maximumItems)),
                id: \.self
            ) { item in
                itemButton(item)
            }
            Menu {
                Menu("Annotations") {
                    ForEach(CaptureToolbarItem.all.filter(\.isAnnotation), id: \.self) { item in
                        menuItem(item)
                    }
                }
                Menu("Image and Recognition") {
                    ForEach(
                        CaptureToolbarItem.all.filter { !$0.isAnnotation && !$0.isAction },
                        id: \.self
                    ) { item in menuItem(item) }
                }
                Menu("Capture and Output") {
                    ForEach(CaptureToolbarAction.allCases, id: \.self) { action in
                        CaptureActionButton(action: action, inMenu: true)
                    }
                }
                Button("Customize Toolbar…") { coordinator.toolbarCustomization.show(coordinator) }
            } label: {
                glyph("ellipsis")
            }
            .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
            .accessibilityLabel(String(localized: "All Tools")).tooltip(String(localized: "All Tools"))
            CaptureIconButton(
                title: String(localized: "Undo"), symbol: "arrow.uturn.backward", shortcut: "⌘Z"
            ) {
                state.finishEditing(); state.undoEdit()
            }.disabled(!state.undo.canUndo)
            CaptureIconButton(
                title: String(localized: "Redo"), symbol: "arrow.uturn.forward", shortcut: "⇧⌘Z"
            ) {
                state.finishEditing(); state.redoEdit()
            }.disabled(!state.undo.canRedo)
        }
        .disabled(state.busy)
    }

    @ViewBuilder private func menuItem(_ item: CaptureToolbarItem) -> some View {
        if item == .annotation(.cover) {
            Menu(LocalizedStringKey(item.title)) { CaptureCensorTools(state: state) }
        } else if item == .suggestCovers {
            Menu(LocalizedStringKey(item.title)) {
                ForEach(CaptureRedactionPolicy.allCases, id: \.self) { policy in
                    Button(LocalizedStringKey(policy.title)) { coordinator.suggestRedactions(policy) }
                }
            }
        } else {
            Button {
                perform(item)
            } label: {
                Label(LocalizedStringKey(item.title), systemImage: selected(item) ? "checkmark" : item.symbol)
            }
        }
    }

    private func itemButton(_ item: CaptureToolbarItem) -> some View {
        action(item).contextMenu {
            if item != .annotation(.select) {
                Button(
                    store.toolbarItems.contains(item)
                        ? String(localized: "Move to All Tools") : String(localized: "Keep in Toolbar")
                ) {
                    store.setToolbarItem(item, visible: !store.toolbarItems.contains(item))
                }
            }
            Button("Reset Toolbar") { store.resetToolbar() }
        }
    }

    @ViewBuilder private func action(_ item: CaptureToolbarItem) -> some View {
        if item == .annotation(.cover) {
            Menu {
                CaptureCensorTools(state: state)
            } label: {
                glyph(item.symbol)
            }
            .menuStyle(CaptureToolbarMenuStyle(selected: selected(item))).fixedSize()
            .accessibilityLabel(Text(LocalizedStringKey(item.title))).tooltip(
                String(localized: "Censor · Solid, Pixelate, Blur, Erase, Text Only"))
        } else if item == .suggestCovers {
            Menu {
                ForEach(CaptureRedactionPolicy.allCases, id: \.self) { policy in
                    Button(LocalizedStringKey(policy.title)) { coordinator.suggestRedactions(policy) }
                }
            } label: {
                glyph(item.symbol)
            }
            .menuStyle(CaptureToolbarMenuStyle()).fixedSize().accessibilityLabel(
                Text(LocalizedStringKey(item.title))
            )
            .tooltip(Bundle.main.localizedString(forKey: item.title, value: nil, table: nil))
        } else {
            CaptureIconButton(
                title: item.title, symbol: item.symbol, shortcut: shortcut(item),
                selected: selected(item),
                hint: item == .annotation(.select)
                    ? String(localized: "Hold ⌥ to move without alignment") : ""
            ) { perform(item) }
        }
    }

    private func shortcut(_ item: CaptureToolbarItem) -> String {
        if case let .annotation(tool) = item { return tool.key.uppercased() }
        return ""
    }

    private func selected(_ item: CaptureToolbarItem) -> Bool {
        switch item {
        case let .annotation(tool):
            CaptureToolbarItem.annotation(state.tool).toolbarEntry == .annotation(tool)
        case .pickColor: state.pickingColor
        case .adjustImage: state.imageAdjustments
        case .beautify: state.presentationControls
        default: false
        }
    }

    private func perform(_ item: CaptureToolbarItem) {
        switch item {
        case let .annotation(tool): state.selectTool(tool)
        case .pickColor:
            state.finishEditing()
            state.pickingColor.toggle()
            state.notice =
                state.pickingColor
                ? String(localized: "Click the image to pick a color. Esc to cancel.") : nil
        case .scanCodes: coordinator.scanCodes()
        case .addImage: coordinator.addImage()
        case .removeBackground: coordinator.removeBackground()
        case .suggestCovers, .action: break
        case .adjustImage:
            state.finishEditing()
            state.tool = .select
            state.selected = nil
            coordinator.expandCapture()
            state.imageAdjustments.toggle()
            state.presentationControls = false
        case .beautify:
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

    private func glyph(_ symbol: String) -> some View {
        CaptureToolbarGlyph(symbol: symbol)
    }
}
