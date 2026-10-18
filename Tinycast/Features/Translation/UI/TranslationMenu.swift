import AppKit
import SwiftUI

enum TranslationMenuKind: Equatable {
    case engine
    case source
    case target
    case actions

    /// Menus opened from the trailing controls hang from their trailing edge.
    var alignsTrailing: Bool { self == .engine || self == .actions }
}

struct TranslationMenuItem: Identifiable {
    let id: String
    let title: String
    var isCurrent = false
    var startsGroup = false
    var shortcut: [String] = []
    let action: () -> Void
}

/// A child window like Notes' heading menu: `PopoverMenu` reads palette state this panel lacks.
@MainActor
final class TranslationMenuWindowController {
    private var panel: TranslationMenuPanel?

    func show(
        _ kind: TranslationMenuKind, rows: Int, groups: Int, anchor: CGRect, above host: NSWindow,
        coordinator: TranslationCoordinator, metrics: InterfaceMetrics
    ) {
        let hosting = NSHostingView(
            rootView: TranslationMenuView(kind: kind).environment(coordinator).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        let panel = panel ?? TranslationMenuPanel()
        self.panel = panel
        panel.contentView = hosting
        let size = CGSize(
            width: metrics.size.formMenuMinimumWidth,
            height: Self.height(rows: rows, groups: groups, metrics: metrics))
        var origin = CGPoint(
            x: host.frame.minX + (kind.alignsTrailing ? anchor.maxX - size.width : anchor.minX),
            y: host.frame.maxY - anchor.maxY - metrics.spacing.xs - size.height)
        if let visible = host.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = max(origin.y, visible.minY)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Matches `TranslationMenuView`'s stack, capped at the palette menus' visible-row height.
    private static func height(rows: Int, groups: Int, metrics: InterfaceMetrics) -> CGFloat {
        let children = CGFloat(rows + groups)
        let content =
            CGFloat(rows) * metrics.size.menuRowHeight
            + max(children - 1, 0) * metrics.size.menuRowSpacing
            + CGFloat(groups) * (Theme.Size.hairline + metrics.spacing.xs * 2)
        return min(content, metrics.size.menuRowsMaxHeight) + metrics.spacing.sm * 2
    }
}

private final class TranslationMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
    }

    /// Never key, so the editor keeps its caret and the panel keeps Escape.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// `PopoverMenuRow`'s look, copied for the same reason Notes copies it.
private struct TranslationMenuView: View {
    let kind: TranslationMenuKind
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        let surface = RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
        let items = coordinator.menuItems(kind)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: metrics.size.menuRowSpacing) {
                    ForEach(items) { item in
                        if item.startsGroup {
                            Rectangle()
                                .fill(Theme.Colors.separator)
                                .frame(height: Theme.Size.hairline)
                                .padding(.vertical, metrics.spacing.xs)
                                .padding(.horizontal, metrics.spacing.md)
                                .accessibilityHidden(true)
                        }
                        TranslationMenuRow(item: item) { coordinator.choose(item) }
                            .id(item.id)
                    }
                }
                .padding(metrics.spacing.sm)
            }
            .scrollBounceBehavior(.basedOnSize)
            .thinScrollbar()
            .onAppear {
                if let current = items.first(where: \.isCurrent) { proxy.scrollTo(current.id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: surface)
        .clipShape(surface)
        .accessibilityElement(children: .contain)
    }
}

private struct TranslationMenuRow: View {
    let item: TranslationMenuItem
    let action: () -> Void
    @Environment(\.metrics) private var metrics
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.spacing.md) {
                Image(systemName: "checkmark")
                    .font(
                        .system(
                            size: metrics.scaled(Theme.Typography.menuSymbolSize),
                            weight: Theme.Typography.menuSymbolWeight))
                    .foregroundStyle(Theme.Colors.menuSymbol)
                    .opacity(item.isCurrent ? 1 : 0)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                Text(item.title)
                    .font(metrics.typography.menuRow)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: metrics.spacing.sm)
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(item.shortcut.enumerated()), id: \.offset) { _, glyph in
                        KeyCapChip(text: glyph, style: .outline)
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: metrics.size.menuRowHeight,
                maxHeight: metrics.size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.isCurrent ? .isSelected : [])
    }
}
