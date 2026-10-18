import SwiftUI

struct DiskUsageList: View {

    @Environment(\.metrics) private var metrics
    let level: DiskUsageLevel?
    let rows: [DiskUsageEntry]
    let selectedID: DiskUsageEntry.ID?
    /// Changes only on keyboard nav / reset, so mouse selection never yanks the scroll position.
    let scroll: ScrollIntent
    let onSelect: (DiskUsageEntry) -> Void
    let onOpen: (DiskUsageEntry) -> Void
    let onActions: (DiskUsageEntry) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == rows.first?.id
    }

    private var summary: String {
        guard let level else { return "" }
        guard level.isComplete else { return level.title }
        return level.title + " · " + CleanupCoordinator.format(level.total)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: summary, isFirst: true)
                    ForEach(rows) { entry in
                        DiskUsageRow(
                            entry: entry, fraction: level?.fraction(of: entry) ?? 0, selected: entry.id == selectedID
                        )
                        .id(entry.id)
                        .selectionFrame(entry.id == selectedID)
                        .contentShape(Rectangle())
                        // Simultaneous, so single-click select never waits on the double-click.
                        .onTapGesture { onSelect(entry) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(entry) })
                        .onRightClick { onActions(entry) }
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
}

private struct DiskUsageRow: View {

    @Environment(\.metrics) private var metrics
    let entry: DiskUsageEntry
    let fraction: Double
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var glyph: String {
        switch entry.kind {
        case .folder: return "folder"
        case .file: return "doc"
        case .unattributed: return "internaldrive"
        case .guarded: return "lock.fill"
        }
    }

    private var size: String {
        if entry.kind == .guarded { return "" }
        guard let bytes = entry.bytes else { return "" }
        return (entry.isPartial ? "≥ " : "") + CleanupCoordinator.format(bytes)
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(name: glyph, size: metrics.size.checkbox)
                .foregroundStyle(entry.kind == .guarded ? Theme.Colors.textTertiary : .secondary)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                HStack(spacing: metrics.spacing.md) {
                    Text(entry.name)
                        .font(metrics.typography.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    Spacer(minLength: metrics.spacing.md)
                    Text(size)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        // The size never yields width; a long folder name truncates instead.
                        .fixedSize()
                }
                // The share of this folder, so the biggest child reads at a glance.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.controlSurface)
                        Capsule()
                            .fill(Theme.Colors.textTertiary)
                            .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: metrics.size.storageBarHeight / 2)
                .opacity(entry.bytes == nil ? 0 : 1)
            }
            if entry.canOpen {
                Image(systemName: "chevron.right")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .opacity(entry.kind == .guarded ? 0.55 : 1)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityValue(size)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The highlighted entry's size, its share of the folder, and where it lives.
struct DiskUsageDetail: View {

    @Environment(\.metrics) private var metrics
    let level: DiskUsageLevel?
    let entry: DiskUsageEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                if let entry { content(entry) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, metrics.spacing.xl)
        }
        .padding(.horizontal, metrics.spacing.xl)
    }

    @ViewBuilder
    private func content(_ entry: DiskUsageEntry) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(entry.name)
                .font(metrics.typography.panelTitle)
                .lineLimit(2)
            if let bytes = entry.bytes {
                Text((entry.isPartial ? "≥ " : "") + CleanupCoordinator.format(bytes))
                    .font(metrics.typography.readout)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                PendingReadout()
            }
            if let level, level.isComplete, entry.bytes != nil {
                let share = level.fraction(of: entry).formatted(.percent.precision(.fractionLength(0)))
                Text(String(localized: "\(share) of everything in \(level.title)"))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        if let explanation = explanation(entry) {
            Text(explanation)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if entry.kind != .unattributed {
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                Text("Information")
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(.secondary)
                HStack(spacing: metrics.spacing.sm) {
                    Text("Where").foregroundStyle(.secondary)
                    Spacer(minLength: metrics.spacing.lg)
                    Text((entry.path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                }
                .font(metrics.typography.keyCap)
                .padding(.vertical, metrics.spacing.xs)
            }
        }
    }

    private func explanation(_ entry: DiskUsageEntry) -> String? {
        switch entry.kind {
        case .folder, .file:
            return DiskUsagePolicy.canTrash(entry.path, home: NSHomeDirectory())
                ? String(localized: "Can be moved to the Trash and put back from there.") : nil
        case .guarded:
            return String(localized: "macOS guards this folder. Allow Full Disk Access to measure it.")
        case .unattributed:
            return String(
                localized: """
                    Space in use that no folder above accounts for: macOS itself, other users, local snapshots \
                    and purgeable caches.
                    """)
        }
    }
}
