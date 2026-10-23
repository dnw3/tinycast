import SwiftUI

/// The proxy window: a sidebar of pages, and the mode and connection in the toolbar.
struct ProxyWindowRootView: View {
    @Environment(AppCore.self) private var core
    @Bindable var state: ProxyWindowState
    @State private var editor: ProxyEditor?

    private var manager: ProxyManager { core.proxy }
    private var coordinator: ProxyCoordinator { core.proxyCoordinator }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(ProxyWindowPage.allCases) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        SymbolImage(name: page.symbol, size: Theme.Size.settingsSidebarGlyph)
                    }
                    .tag(page)
                }
            }
            .safeAreaInset(edge: .bottom) { ProxyWindowStatusLine(manager: manager) }
            // Ahead of the width: applied after it, the column shrinks to AppKit's default.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(
                min: Theme.Size.settingsSidebar, ideal: Theme.Size.settingsSidebar,
                max: Theme.Size.settingsSidebar)
        } detail: {
            detail
                .frame(minWidth: Theme.Size.settingsDetailMinimum)
        }
        .navigationTitle(Text(state.page.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProxyModePicker(manager: manager, coordinator: coordinator)
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: connection) {
                    Text("Connected")
                }
                .toggleStyle(.switch)
                .disabled(!manager.store.profile.isEnabled)
                .help(Text(manager.store.wantsConnection ? "Disconnect" : "Connect"))
            }
        }
        .settingsEditorPanel(item: $editor) { editor in
            ProxyEditorPanel(
                editor: editor, manager: manager, replace: { self.editor = $0 }, close: { self.editor = nil })
        }
        .onChange(of: state.editRequest?.id, initial: true) { _, _ in
            guard let request = state.editRequest else { return }
            state.editRequest = nil
            handle(request.kind)
        }
        .onChange(of: state.page, initial: true) { _, page in coordinator.windowShows(page) }
        .onDisappear { coordinator.windowShows(nil) }
        .environment(\.proxyOpenEditor, ProxyOpenEditorAction { editor = $0 })
        .environment(state)
    }

    @ViewBuilder private var detail: some View {
        switch state.page {
        case .overview: ProxyOverviewPane(manager: manager)
        case .nodes: ProxyNodesPane(manager: manager, state: state)
        case .routes: ProxyRoutesPane(manager: manager)
        case .sources: ProxySourcesPane(manager: manager)
        case .activity: ProxyActivityPane(manager: manager)
        }
    }

    private var selection: Binding<ProxyWindowPage?> {
        Binding(get: { state.page }, set: { if let page = $0 { state.page = page } })
    }

    private var connection: Binding<Bool> {
        Binding(
            get: { manager.store.wantsConnection },
            set: { $0 ? coordinator.connect() : coordinator.disconnect() })
    }

    private func handle(_ request: ProxyEditRequest.Kind) {
        let profile = manager.store.profile
        switch request {
        case .addSubscription(let link, let connects):
            state.page = .sources
            editor = .source(.newSubscription(link: link ?? "", connects: connects))
        case .importFile:
            state.page = .sources
            coordinator.importNodeFiles()
        case .editSource(let id):
            state.page = .sources
            if let source = profile.sources.first(where: { $0.id == id }) {
                editor = .source(.existing(source, in: manager.store))
            }
        case .newStrategy(let route):
            state.page = .nodes
            editor = .strategy(ProxyStrategyDraft.new(in: profile, forRoute: route))
        case .editStrategy(let id):
            state.page = .nodes
            state.nodesTab = .strategy(id)
            if let strategy = profile.strategy(id) { editor = .strategy(ProxyStrategyDraft(strategy: strategy)) }
        case .editRules:
            state.page = .routes
            editor = .rules
        case .addRoute:
            state.page = .routes
            editor = .addRoute
        }
    }
}

/// Opens an editor panel over the proxy window, from any page.
struct ProxyOpenEditorAction {
    private let action: (ProxyEditor) -> Void

    init(_ action: @escaping (ProxyEditor) -> Void = { _ in }) {
        self.action = action
    }

    func callAsFunction(_ editor: ProxyEditor) {
        action(editor)
    }
}

extension EnvironmentValues {
    @Entry var proxyOpenEditor = ProxyOpenEditorAction()
}

/// Rule, global or direct, the same three the menu bar and the launcher offer.
struct ProxyModePicker: View {
    let manager: ProxyManager
    let coordinator: ProxyCoordinator

    var body: some View {
        Picker(selection: Binding(get: { manager.mode }, set: { coordinator.setMode($0) })) {
            ForEach(ProxyMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            Text("Mode")
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help(Text(manager.mode.explanation))
    }
}

/// Whether the proxy is connected, and how, under the sidebar.
private struct ProxyWindowStatusLine: View {
    let manager: ProxyManager

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
                .accessibilityHidden(true)
            Text(manager.statusTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var color: Color {
        switch manager.status {
        case .running: Theme.Colors.success
        case .starting: Theme.Colors.warning
        case .failed: Theme.Colors.destructive
        case .off: Theme.Colors.textTertiary
        }
    }
}
