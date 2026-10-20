import AppKit
import SwiftUI

/// A real split view, as Settings has, so the sidebar collapses and resizes like a native one.
final class AIChatSplitViewController: NSSplitViewController {
    private static let autosaveName = "AIChatSplitView"

    private let peek: AIChatSidebarPeek
    private var collapse: NSKeyValueObservation?

    init(sidebar: some View, detail: some View, peek: AIChatSidebarPeek) {
        self.peek = peek
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar))
        sidebarItem.minimumThickness = Theme.Size.aiChatSidebarMinimum
        sidebarItem.maximumThickness = Theme.Size.aiChatSidebarMaximum
        sidebarItem.canCollapse = true

        let detailItem = NSSplitViewItem(viewController: NSHostingController(rootView: detail))
        detailItem.minimumThickness = Theme.Size.aiChatDetailMinimum

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.autosaveName = Self.autosaveName
        // Changes from ⌘B, the divider and a narrowing window alike, as the item reports them.
        collapse = sidebarItem.observe(\.isCollapsed, options: [.initial]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reportSidebar() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The autosaved state lands with the first layout, after the observation's initial report.
    override func viewDidAppear() {
        super.viewDidAppear()
        reportSidebar()
    }

    /// A slid-out sidebar pins where it stands: the split view's own takes its place, unanimated.
    override func toggleSidebar(_ sender: Any?) {
        guard peek.isShown, let sidebar = splitViewItems.first, sidebar.isCollapsed else {
            super.toggleSidebar(sender)
            return
        }
        peek.pin()
        sidebar.isCollapsed = false
    }

    /// Read as it changes, when its frame still has the width it is leaving or arriving at.
    private func reportSidebar() {
        guard let sidebar = splitViewItems.first else { return }
        peek.isCollapsed = sidebar.isCollapsed
        let width = sidebar.viewController.view.frame.width
        if width > 0 { peek.width = width }
        if !sidebar.isCollapsed { peek.pin() }
    }
}
