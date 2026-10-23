import AppKit
import SwiftUI

/// The proxy window: status, nodes, routing, subscriptions and activity, built like Settings.
@MainActor
final class ProxyWindowController {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore
    /// The open window's state; its view tree owns it, so this self-nils when the window closes.
    private weak var state: ProxyWindowState?
    private weak var editorPresenter: SettingsEditorPresenter?

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: String(localized: "Proxy"), contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "ProxyWindow", activation: core.activationPolicy)
    }

    /// An open window moves to `page`, and opens `edit` over it; a nil page keeps the one it shows.
    func show(page: ProxyWindowPage? = nil, edit: ProxyEditRequest.Kind? = nil) {
        if window.focus(), let state {
            if let page { state.page = page }
            if let edit { state.editRequest = ProxyEditRequest(kind: edit) }
            return
        }
        let state = ProxyWindowState(page: page ?? .overview)
        state.editRequest = edit.map { ProxyEditRequest(kind: $0) }
        // Its own navigation, so an editor here never moves Settings to another pane.
        let navigation = SettingsNavigationState(tab: .proxy)
        let editorPresenter = SettingsEditorPresenter(core: core, navigation: navigation)
        self.state = state
        self.editorPresenter = editorPresenter
        let hosting = NSHostingController(
            rootView: ProxyWindowRootView(state: state).settingsEnvironment(
                core: core, navigation: navigation, editorPresenter: editorPresenter))
        // Keep the window's size authoritative: an unconstrained fill would drive the frame.
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.show(chrome: SettingsWindowChrome()) { hosting }
        editorPresenter.attach(to: hosting.view.window)
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    func close() {
        editorPresenter?.dismissAll()
        window.close()
    }

    /// A sheet on the window follows it into a full-screen space, where a free panel would not.
    func runSheet(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await window.runSheet(panel)
    }
}
