import SwiftUI

/// One row of a proxy screen: what it names, where its traffic goes now, and how fast that is.
struct ProxyPaletteRow: Identifiable, Equatable {
    enum Leading: Equatable {
        case tint(ProxyStrategy.Tint)
        case symbol(String)
        /// A region's flag, or a globe where there is none to show.
        case flag(String?)
    }

    enum Tone: Equatable {
        case secondary
        case good
        case slow
        case danger
    }

    let id: String
    /// Consecutive rows with one section title share its header.
    var section: String?
    var leading: Leading
    var title: String
    var subtitle: String?
    var trailing: String?
    var trailingTone = Tone.secondary
    /// What traffic takes now, marked so the choice reads at a glance.
    var isCurrent = false
    var isDimmed = false
}

extension ProxyPaletteRow.Tone {
    init(_ delay: ProxyDelay) {
        switch delay {
        case .untested: self = .secondary
        case .failed: self = .danger
        case .milliseconds: self = delay.isSlow ? .slow : .good
        }
    }

    var color: Color {
        switch self {
        case .secondary: .secondary
        case .good: .green
        case .slow: .orange
        case .danger: .red
        }
    }
}

extension ProxyPaletteRow.Leading {
    static func target(_ target: ProxyTarget, in profile: ProxyProfile) -> Self {
        switch target {
        case .direct: .symbol("arrow.right")
        case .reject: .symbol("nosign")
        case .strategy(let id): profile.strategy(id).map { .tint($0.tint) } ?? .symbol("questionmark")
        }
    }
}

/// The sectioned list every proxy screen draws, so they share one row and one scroll behaviour.
struct ProxyPaletteList: View {
    @Environment(\.metrics) private var metrics
    let rows: [ProxyPaletteRow]
    let selectedID: String?
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    private enum Line: Identifiable {
        case header(String, isFirst: Bool)
        case row(Int)

        var id: String {
            switch self {
            case .header(let title, _): "header-" + title
            case .row(let index): "row-\(index)"
            }
        }
    }

    private var lines: [Line] {
        var lines: [Line] = []
        var section: String?
        for (index, row) in rows.enumerated() {
            if let title = row.section, title != section {
                lines.append(.header(title, isFirst: lines.isEmpty))
            }
            section = row.section
            lines.append(.row(index))
        }
        return lines
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lines) { line in
                        switch line {
                        case .header(let title, let isFirst):
                            SectionHeader(title: title, isFirst: isFirst)
                        case .row(let index):
                            let row = rows[index]
                            ProxyPaletteRowView(row: row, selected: row.id == selectedID)
                                .id(row.id)
                                .selectionFrame(row.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(index) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onActivate(index) })
                                .onRightClick {
                                    onSelect(index)
                                    onActions(index)
                                }
                        }
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
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: selectedID != nil && selectedID == rows.first?.id,
                proxy: proxy)
        }
    }
}

private struct ProxyPaletteRowView: View {
    @Environment(\.metrics) private var metrics
    let row: ProxyPaletteRow
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            leading
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(row.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .layoutPriority(1)
            if let subtitle = row.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            if let trailing = row.trailing {
                Text(trailing)
                    .font(metrics.typography.rowTrailing.monospacedDigit())
                    .foregroundStyle(row.trailingTone.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            if row.isCurrent {
                Image(systemName: "checkmark")
                    .font(metrics.typography.rowTrailing.weight(.semibold))
                    .foregroundStyle(Theme.Colors.brand)
                    .accessibilityLabel(String(localized: "In use"))
            }
        }
        .opacity(row.isDimmed ? 0.5 : 1)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var leading: some View {
        switch row.leading {
        case .tint(let tint):
            ProxyTintDot(tint: tint, size: metrics.size.resultRowIcon * 0.55)
        case .symbol(let name):
            SymbolImage(name: name, size: metrics.size.resultRowIcon * 0.7)
                .foregroundStyle(.secondary)
        case .flag(let flag?):
            ProxyFlag(emoji: flag, size: metrics.size.resultRowIcon * 0.8)
                .font(.system(size: metrics.size.resultRowIcon * 0.8))
        case .flag(nil):
            SymbolImage(name: "globe", size: metrics.size.resultRowIcon * 0.7)
                .foregroundStyle(.secondary)
        }
    }
}

/// What a screen is about, beside its search field: the route being picked for, or a strategy.
@MainActor
enum ProxyContextChip {
    static func accessory(
        title: String, leading: ProxyPaletteRow.Leading, metrics: InterfaceMetrics
    ) -> PaletteHeaderAccessory {
        let text = (title as NSString).size(withAttributes: [.font: metrics.typography.chipNSFont]).width
        let width = ceil(text) + metrics.size.menuIcon + metrics.spacing.sm * 2 + metrics.spacing.md * 2
        return PaletteHeaderAccessory(
            width: width, fieldNames: [], firstIncompleteField: nil, placement: .besideSearchField,
            view: AnyView(ProxyContextChipView(title: title, leading: leading)))
    }
}

private struct ProxyContextChipView: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let leading: ProxyPaletteRow.Leading

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            switch leading {
            case .tint(let tint): ProxyTintDot(tint: tint, size: metrics.size.menuIcon * 0.6)
            case .symbol(let name):
                SymbolImage(name: name, size: metrics.size.menuIcon * 0.7).foregroundStyle(.secondary)
            case .flag(let flag?): ProxyFlag(emoji: flag, size: metrics.typography.chipNSFont.pointSize)
            case .flag(nil): Text(verbatim: "🌐")
            }
            Text(title).lineLimit(1)
        }
        .font(metrics.typography.chip)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.xs)
        .background(Capsule().fill(Theme.Colors.controlSurface))
        .fixedSize()
    }
}
