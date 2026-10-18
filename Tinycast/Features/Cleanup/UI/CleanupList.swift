import SwiftUI

struct CleanupList: View {

    @Environment(\.metrics) private var metrics
    let rows: [CleanupRow]
    let scope: CleanupScreen.Scope
    let session: CleanupSession
    let selectedID: CleanupRow.ID?
    /// Changes only on keyboard nav / reset, so mouse selection never yanks the scroll position.
    let scroll: ScrollIntent
    let appName: (String) -> String
    let onSelect: (CleanupRow) -> Void
    let onToggle: (CleanupRow) -> Void
    let onOpen: (CleanupRow) -> Void
    let onActions: (CleanupRow) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == rows.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if let title = header(before: index) {
                            SectionHeader(title: title, isFirst: index == 0)
                        }
                        CleanupRowView(
                            row: row, session: session, selected: row.id == selectedID, appName: appName,
                            onToggle: { onToggle(row) }
                        )
                        .id(row.id)
                        .selectionFrame(row.id == selectedID)
                        .contentShape(Rectangle())
                        // Simultaneous, so single-click select never waits on the double-click.
                        .onTapGesture { onSelect(row) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(row) })
                        .onRightClick { onActions(row) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }

    /// A category title where the list crosses into a new one; the group scope titles its group.
    private func header(before index: Int) -> String? {
        switch scope {
        case .group:
            guard index == 0, let id = session.focusedGroupID else { return nil }
            let items = session.focusedItems
            let checked = items.filter { session.isChecked($0) }
            let bytes = checked.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            return String(
                localized: "\(id.title) · \(checked.count) of \(items.count) selected · \(CleanupCoordinator.format(bytes))")
        case .root:
            guard let category = category(of: rows[index]) else { return nil }
            if index > 0, self.category(of: rows[index - 1]) == category { return nil }
            return category.title
        }
    }

    private func category(of row: CleanupRow) -> CleanupCategory? {
        guard case .group(let id) = row else { return nil }
        return CleanupCatalog.target(id).category
    }
}

private struct CleanupRowView: View {

    @Environment(\.metrics) private var metrics
    let row: CleanupRow
    let session: CleanupSession
    let selected: Bool
    let appName: (String) -> String
    let onToggle: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private struct Content {
        var glyph: String
        var title: String
        var trailing: String = ""
        var isLocked = false
        var isCheckbox = true
        var drills = false
        var tooltip: String?
    }

    private var content: Content {
        switch row {
        case .overview:
            let available = session.capacity.map { CleanupCoordinator.format($0.available) } ?? ""
            return Content(
                glyph: "internaldrive", title: String(localized: "Disk Overview"),
                trailing: available.isEmpty ? "" : String(localized: "\(available) available"), isCheckbox: false)
        case .access:
            return Content(
                glyph: "lock.shield", title: String(localized: "Allow Full Disk Access to find more"),
                isCheckbox: false)
        case .group(let id):
            guard let group = session.plan.group(id) else { return Content(glyph: "square", title: id.title) }
            let available = session.isAvailable(group)
            let glyph: String
            if !group.target.isSelectable {
                glyph = "trash"
            } else if !available {
                glyph = "lock.fill"
            } else {
                switch session.state(of: group) {
                case .on: glyph = "checkmark.square.fill"
                case .off: glyph = "square"
                case .mixed: glyph = "minus.square.fill"
                }
            }
            let lockReason = group.items.first.flatMap(session.lock)?.reason(appName: appName)
            return Content(
                glyph: glyph, title: id.title, trailing: size(group.items),
                isLocked: group.target.isSelectable && !available, isCheckbox: group.target.isSelectable,
                drills: group.items.count > 1 || group.target.isGeneric,
                tooltip: available ? nil : lockReason)
        case .item(let path):
            guard let item = session.plan.item(path) else { return Content(glyph: "square", title: "") }
            let lock = session.lock(item)
            let glyph = lock != nil ? "lock.fill" : (session.isChecked(item) ? "checkmark.square.fill" : "square")
            return Content(
                glyph: item.target.isSelectable ? glyph : "doc", title: item.name, trailing: size([item]),
                isLocked: lock != nil, isCheckbox: item.target.isSelectable, tooltip: lock?.reason(appName: appName))
        }
    }

    private func accessibilityValue(_ content: Content) -> String {
        var parts: [String] = []
        if content.isLocked {
            parts.append(content.tooltip ?? String(localized: "Locked"))
        } else if content.isCheckbox {
            switch content.glyph {
            case "checkmark.square.fill": parts.append(String(localized: "Selected"))
            case "minus.square.fill": parts.append(String(localized: "Partly selected"))
            default: parts.append(String(localized: "Not selected"))
            }
        }
        if !content.trailing.isEmpty { parts.append(content.trailing) }
        return parts.joined(separator: ", ")
    }

    private func size(_ items: [CleanupItem]) -> String {
        CleanupItem.sizeLabel(items)
    }

    var body: some View {
        let content = content
        HStack(spacing: metrics.spacing.lg) {
            // One glyph size in the result-row slot, so titles line up and match Disk Usage.
            SymbolImage(name: content.glyph, size: metrics.size.checkbox)
                .foregroundStyle(content.isLocked ? Theme.Colors.textTertiary : .primary)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .contentShape(Rectangle())
                // Only the checkbox toggles; the rest of the row selects.
                .onTapGesture { if content.isCheckbox, !content.isLocked { onToggle() } }
                .tooltip(content.tooltip)
            Text(content.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: metrics.spacing.md)
            Text(content.trailing)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                // The size never yields width; a long folder name truncates instead.
                .fixedSize()
            if content.drills {
                Image(systemName: "chevron.right")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .opacity(content.isLocked ? 0.55 : 1)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.title)
        .accessibilityValue(accessibilityValue(content))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
