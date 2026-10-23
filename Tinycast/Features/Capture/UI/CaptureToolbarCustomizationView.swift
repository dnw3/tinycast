import SwiftUI

struct CaptureToolbarCustomizationView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var query = ""
    @State private var actions = false
    @State private var selection = Set<CaptureToolbarItem>()
    private var store: CaptureSettingsStore { coordinator.settings }
    private var group: [CaptureToolbarItem] {
        store.toolbarConfiguration.orderedItems(actions: actions, visibleOnly: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            Text("Customize Capture Toolbar").font(metrics.typography.panelTitle)
            preview(actions: false)
            preview(actions: true)
            SteadySegmentedPicker(
                title: String(localized: "Toolbar"),
                options: [
                    .init(value: false, title: String(localized: "Annotations")),
                    .init(value: true, title: String(localized: "Capture and Output"))
                ],
                selection: $actions
            )
            .fixedSize()
            SettingsFilterField(prompt: "Search tools or shortcuts", query: $query)
                .accessibilityLabel(String(localized: "Search Tools"))
            List(selection: $selection) {
                ForEach(group.filter { $0.matches(query) }, id: \.self) { item in
                    row(item)
                        .tag(item)
                        .moveDisabled(item == .annotation(.select) || !query.isEmpty)
                }
                .onMove { offsets, destination in
                    guard query.isEmpty else { return }
                    store.reorderToolbar(actions: actions, from: offsets, to: destination)
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
            Text(
                query.isEmpty
                    ? String(localized: "Drag rows to reorder. Checked tools appear in the toolbar.")
                    : String(localized: "Clear search to reorder tools.")
            )
            .font(metrics.typography.bar).foregroundStyle(Theme.Colors.textSecondary)
            HStack {
                Button("Reset Toolbar") { store.resetToolbar() }
                    .buttonStyle(.modalAction(.standard, fillsWidth: false))
                Spacer()
                Button("Done") {
                    coordinator.toolbarCustomization.close(); _ = coordinator.overlay.focusExisting()
                }
                .buttonStyle(.modalAction(.primary, fillsWidth: false))
                .keyboardShortcut(.defaultAction)
            }
        }
        .onExitCommand {
            coordinator.toolbarCustomization.close(); _ = coordinator.overlay.focusExisting()
        }
        .onChange(of: actions) { selection.removeAll() }
        .onChange(of: query) { selection.removeAll() }
        .padding(metrics.spacing.xl)
        .foregroundStyle(Theme.Colors.textPrimary)
        .captureWindowSurface()
    }

    private func preview(actions: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(
                actions
                    ? String(localized: "Action Toolbar · top to bottom")
                    : String(localized: "Annotation Toolbar · left to right")
            )
            .font(metrics.typography.bar).foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: metrics.spacing.xxs) {
                ForEach(
                    Array(store.toolbarConfiguration.orderedItems(actions: actions).prefix(14)), id: \.self
                ) { item in
                    CaptureToolbarGlyph(symbol: item.symbol)
                        .frame(
                            width: metrics.scaled(Theme.Size.captureTool),
                            height: metrics.scaled(Theme.Size.captureTool))
                }
                if !actions {
                    CaptureToolbarGlyph(symbol: "ellipsis")
                        .frame(
                            width: metrics.scaled(Theme.Size.captureTool),
                            height: metrics.scaled(Theme.Size.captureTool))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped().accessibilityElement(children: .ignore)
            .accessibilityLabel(
                actions
                    ? String(localized: "Action Toolbar Preview")
                    : String(localized: "Annotation Toolbar Preview")
            )
            .accessibilityValue(
                store.toolbarConfiguration.orderedItems(actions: actions).map {
                    Bundle.main.localizedString(forKey: $0.title, value: nil, table: nil)
                }.joined(separator: ", "))
        }
    }

    private func row(_ item: CaptureToolbarItem) -> some View {
        HStack(spacing: metrics.spacing.md) {
            CaptureToolbarGlyph(symbol: item.symbol)
            Toggle(
                LocalizedStringKey(item.title),
                isOn: Binding(
                    get: { store.toolbarItems.contains(item) },
                    set: { store.setToolbarItem(item, visible: $0) })
            )
            .toggleStyle(.checkbox).disabled(item == .annotation(.select))
            Spacer()
            CaptureToolbarGlyph(symbol: "line.3.horizontal")
                .foregroundStyle(Theme.Colors.textTertiary).accessibilityHidden(true)
        }.padding(.vertical, metrics.spacing.xxs)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Move Up") {
                if query.isEmpty { store.moveToolbarItem(item, by: -1) }
            }
            .accessibilityAction(named: "Move Down") {
                if query.isEmpty { store.moveToolbarItem(item, by: 1) }
            }
            .contextMenu {
                Button("Move Up") { store.moveToolbarItem(item, by: -1) }
                    .disabled(!query.isEmpty || item == .annotation(.select) || group.first == item)
                Button("Move Down") { store.moveToolbarItem(item, by: 1) }
                    .disabled(!query.isEmpty || item == .annotation(.select) || group.last == item)
            }
    }

}
