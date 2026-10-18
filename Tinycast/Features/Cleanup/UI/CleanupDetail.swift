import SwiftUI

/// The right pane: what the highlighted row is, how it is handled and where it lives.
struct CleanupDetail: View {

    @Environment(\.metrics) private var metrics
    let row: CleanupRow?
    let session: CleanupSession
    let appName: (String) -> String
    var history: CleanupScheduleStore?

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    @MainActor private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                switch row {
                case .overview: overview
                case .access: access
                case .group(let id): group(id)
                case .item(let path): item(path)
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, metrics.spacing.xl)
        }
        .padding(.horizontal, metrics.spacing.xl)
    }

    // MARK: - Overview

    @ViewBuilder private var overview: some View {
        heading(
            title: String(localized: "Can Be Cleaned"),
            readout: session.isScanning && session.reclaimableBytes == 0
                ? "—" : CleanupCoordinator.format(session.reclaimableBytes),
            caption: status)
        if let capacity = session.capacity {
            StorageBar(total: capacity.total, available: capacity.available, selected: session.selectedBytes)
        }
        if let last = history?.lastRun {
            info(
                [
                    InfoRow(
                        label: String(localized: "Last Cleanup"),
                        value: last.date.formatted(date: .abbreviated, time: .shortened)),
                    InfoRow(
                        label: String(localized: "Freed in Total"),
                        value: CleanupCoordinator.format(history?.totalFreed ?? 0))
                ], title: String(localized: "History"))
        }
        let categories = CleanupCategory.allCases.filter { session.bytes(in: $0) > 0 }
        if !categories.isEmpty {
            info(
                categories.map { InfoRow(label: $0.title, value: CleanupCoordinator.format(session.bytes(in: $0))) },
                title: String(localized: "By Category"))
        }
    }

    private var status: String? {
        switch session.phase {
        case .idle, .discovering: return String(localized: "Scanning…")
        case .measuring: return String(localized: "Measuring sizes…")
        case .ready: return session.isCleaning ? String(localized: "Cleaning…") : nil
        }
    }

    // MARK: - Access

    @ViewBuilder private var access: some View {
        heading(title: String(localized: "Full Disk Access"), readout: nil, caption: nil)
        paragraph(
            String(
                localized: """
                    Sandboxed apps keep their caches in folders macOS guards, along with Messages and the Trash. \
                    Turn on Tinycast under Privacy & Security › Full Disk Access.
                    """))
    }

    // MARK: - Group

    @ViewBuilder private func group(_ id: CleanupTargetID) -> some View {
        if let group = session.plan.group(id) {
            heading(title: id.title, readout: readout(group.items), caption: group.target.handling)
            paragraph(id.explanation)
            if let first = group.items.first, let lock = session.lock(first), !session.isAvailable(group) {
                paragraph(lock.reason(appName: appName), tone: .warning)
            }
            info(groupRows(group))
            let largest = group.items.filter { $0.size != nil }.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.prefix(5)
            if group.items.count > 1, !largest.isEmpty {
                info(
                    largest.map { InfoRow(label: $0.name, value: CleanupCoordinator.format($0.size ?? 0)) },
                    title: String(localized: "Largest"))
            }
        }
    }

    private func groupRows(_ group: CleanupGroup) -> [InfoRow] {
        if let tool = CleanupTool(target: group.id), let item = group.items.first {
            return Self.commandRows(tool, item: item)
        }
        var rows = [InfoRow(label: String(localized: "Items"), value: group.items.count.formatted())]
        if group.items.count == 1, let item = group.items.first {
            rows.append(InfoRow(label: String(localized: "Where"), value: Self.abbreviate(item.path)))
        }
        if let modified = group.items.compactMap(\.modified).max() {
            rows.append(
                InfoRow(label: String(localized: "Last Modified"), value: Self.stampFormatter.string(from: modified)))
        }
        return rows
    }

    // MARK: - Item

    @ViewBuilder private func item(_ path: String) -> some View {
        if let item = session.plan.item(path) {
            heading(title: item.name, readout: readout([item]), caption: item.target.handling)
            if let lock = session.lock(item) {
                paragraph(lock.reason(appName: appName), tone: .warning)
            }
            info(itemRows(item))
            paragraph(item.target.id.explanation)
        }
    }

    private static func commandRows(_ tool: CleanupTool, item: CleanupItem) -> [InfoRow] {
        let arguments = tool == .localSnapshots
            ? item.match.captures.first.flatMap { tool.arguments(snapshot: $0) } : tool.arguments()
        var rows = [
            InfoRow(
                label: String(localized: "Command"),
                value: ([tool.executable] + (arguments ?? [])).joined(separator: " "))
        ]
        if item.isOnDisk { rows.append(InfoRow(label: String(localized: "Where"), value: abbreviate(item.path))) }
        if tool == .localSnapshots || tool == .simulators {
            rows.append(InfoRow(label: String(localized: "Items"), value: item.match.captures.count.formatted()))
        }
        return rows
    }

    private func itemRows(_ item: CleanupItem) -> [InfoRow] {
        if let tool = CleanupTool(target: item.match.target) { return Self.commandRows(tool, item: item) }
        var rows = [
            InfoRow(label: String(localized: "Where"), value: Self.abbreviate(item.path)),
            InfoRow(label: String(localized: "Kind"), value: item.target.id.title)
        ]
        if item.match.target == .duplicates, let keeper = item.match.captures.first {
            rows.append(InfoRow(label: String(localized: "Kept Copy"), value: Self.abbreviate(keeper)))
        }
        if item.target.source == .project, let root = item.match.captures.first {
            let folder = String(item.path.dropFirst(root.count + 1))
            rows.append(InfoRow(label: String(localized: "Project"), value: Self.abbreviate(root)))
            if let rule = CleanupProjectRules.rules.first(where: { $0.folder == folder }) {
                rows.append(InfoRow(label: String(localized: "Rebuild With"), value: rule.rebuild))
            }
            if let modified = item.modified {
                rows.append(
                    InfoRow(label: String(localized: "Last Edited"), value: Self.stampFormatter.string(from: modified)))
            }
            return rows
        }
        if let modified = item.modified {
            rows.append(
                InfoRow(label: String(localized: "Last Modified"), value: Self.stampFormatter.string(from: modified)))
        }
        return rows
    }

    // MARK: - Pieces

    private func readout(_ items: [CleanupItem]) -> String {
        CleanupItem.sizeLabel(items, pending: "—")
    }

    @ViewBuilder
    private func heading(title: String, readout: String?, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(title)
                .font(metrics.typography.panelTitle)
                .lineLimit(2)
            if let readout {
                Text(readout)
                    .font(metrics.typography.readout)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if let caption {
                Text(caption)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private enum Tone {
        case plain
        case warning
    }

    private func paragraph(_ text: String, tone: Tone = .plain) -> some View {
        Text(text)
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(tone == .warning ? Theme.Colors.warning : Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func info(_ rows: [InfoRow], title: String = String(localized: "Information")) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(title)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle).monospacedDigit()
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
    }

    private static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
