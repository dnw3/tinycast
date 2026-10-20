import AppKit
import SwiftUI

/// Slides AI Chat's hidden sidebar out over the transcript when the pointer rests on the left edge.
struct AIChatSidebarPeekEdge: ViewModifier {
    @Environment(AIChatCoordinator.self) private var coordinator
    @Environment(AIChatSidebarPeek.self) private var peek
    @State private var toolbarHeight: CGFloat = 0
    /// Arriving at the edge from outside the window, as a pass to another app does, never counts.
    @State private var cameFromInside = false
    @State private var pointer: CGPoint?
    @State private var arming: Task<Void, Never>?
    @State private var leaving: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                toolbarHeight = $0
            }
            .overlay(alignment: .leading) {
                if peek.isShown {
                    sidebar.transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): moved(to: location)
                case .ended: left()
                }
            }
    }

    /// Where the pinned sidebar would stand, from the window's top, the toolbar's buttons on it.
    private var sidebar: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.aiChatSidebarPeek, style: .continuous)
        return AIChatSidebarView()
            .padding(.top, max(toolbarHeight - Theme.Spacing.md, 0))
            .frame(width: max(peek.width - Theme.Spacing.md * 2, 0))
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: shape)
            // Solid under the glass: the transcript it covers must not read through the list.
            .background { shape.fill(Theme.Colors.windowSurface) }
            .clipShape(shape)
            .shadow(color: Theme.Colors.tooltipShadow, radius: Theme.Spacing.xl, y: Theme.Spacing.xs)
            .padding(Theme.Spacing.md)
            .ignoresSafeArea()
    }

    private func moved(to location: CGPoint) {
        pointer = location
        if peek.isShown {
            if location.x <= peek.width { stopLeaving() } else { scheduleLeaving() }
            return
        }
        guard location.x <= Theme.Size.aiChatSidebarPeekEdge else {
            cameFromInside = true
            stopArming()
            return
        }
        arm()
    }

    private func arm() {
        guard cameFromInside, arming == nil, peek.isCollapsed, coordinator.isWindowKey,
            coordinator.aiSettings.sidebarPeekEnabled, NSEvent.pressedMouseButtons == 0
        else { return }
        arming = Task {
            try? await Task.sleep(for: .seconds(Theme.Duration.sidebarPeekDwell))
            guard !Task.isCancelled else { return }
            arming = nil
            // A drag that began on the way, a resize or a selection, is not a request to see it.
            guard pointerIsAtEdge, NSEvent.pressedMouseButtons == 0 else { return }
            peek.show()
        }
    }

    /// Hover ends at the window's edge, so a slight overshoot past it is checked on the screen.
    private func left() {
        if let pointer, pointer.x <= Theme.Size.aiChatSidebarPeekEdge, !peek.isShown {
            arm()
        } else {
            stopArming()
        }
        cameFromInside = false
        self.pointer = nil
        if peek.isShown { scheduleLeaving() }
    }

    private var pointerIsAtEdge: Bool {
        guard let point = pointerInWindow else { return false }
        return (-Theme.Size.aiChatSidebarPeekOvershoot...Theme.Size.aiChatSidebarPeekEdge)
            .contains(point.x)
    }

    /// Rechecked each beat: hover ends in the toolbar's band, though the sidebar runs under it.
    private func scheduleLeaving() {
        guard leaving == nil else { return }
        leaving = Task {
            repeat {
                try? await Task.sleep(for: .seconds(Theme.Duration.sidebarPeekLinger))
                guard !Task.isCancelled else { return }
            } while peek.isShown && (isEditingInside || pointerIsOverSidebar)
            leaving = nil
            peek.hide()
        }
    }

    /// Typing in its filter or a rename keeps it out, wherever the pointer wanders meanwhile.
    private var isEditingInside: Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor
        else { return false }
        return editor.convert(editor.bounds, to: nil).minX < peek.width
    }

    private var pointerIsOverSidebar: Bool {
        guard let point = pointerInWindow, point.x >= 0 else { return false }
        return point.x <= peek.width
    }

    /// The pointer in the key AI Chat window's coordinates, while it is level with the content.
    private var pointerInWindow: CGPoint? {
        guard let window = NSApp.keyWindow, let content = window.contentView,
            window.identifier == AIChatWindowChrome.windowIdentifier
        else { return nil }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return (content.frame.minY...content.frame.maxY).contains(point.y) ? point : nil
    }

    private func stopLeaving() {
        leaving?.cancel()
        leaving = nil
    }

    private func stopArming() {
        arming?.cancel()
        arming = nil
    }
}
