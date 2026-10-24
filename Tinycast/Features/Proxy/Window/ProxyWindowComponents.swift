import SwiftUI

/// A page of the proxy window: a scrolling column of cards, inset like a Settings pane.
struct ProxyPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xxl)
        }
    }
}

/// A rounded group on a page, filled and stroked with the card tokens.
struct ProxyCard<Content: View>: View {
    var padding = Theme.Spacing.xl
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(shape.fill(Theme.Colors.cardFill))
            .overlay(shape.strokeBorder(Theme.Colors.cardStroke))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }
}

/// A heading over a group of cards, with a caption and the group's own buttons.
struct ProxySectionHeader<Accessory: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(title).font(.headline)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            accessory
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

extension ProxySectionHeader where Accessory == EmptyView {
    init(title: String, caption: String? = nil) {
        self.init(title: title, caption: caption) { EmptyView() }
    }
}

/// A note at the top of a page, such as why the routes do not apply in global mode.
struct ProxyNote<Accessory: View>: View {
    let text: String
    var symbol = "info.circle"
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ProxyCard {
            HStack(spacing: Theme.Spacing.md) {
                SymbolImage(name: symbol, size: Theme.Size.settingsSidebarGlyph).foregroundStyle(.secondary)
                Text(text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.md)
                accessory
            }
        }
    }
}

extension ProxyNote where Accessory == EmptyView {
    init(text: String, symbol: String = "info.circle") {
        self.init(text: text, symbol: symbol) { EmptyView() }
    }
}

/// Its subviews in a row at their ideal size, starting another row when the next would not fit.
struct ProxyWrapLayout: Layout {
    var spacing = Theme.Spacing.sm

    private struct Row {
        var indices: [Int] = []
        var width = 0.0
        var height = 0.0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * Double(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(of subviews: Subviews, width: Double) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, !last.indices.isEmpty, last.width + spacing + size.width > width {
                rows.append(Row())
            }
            rows[rows.count - 1].width += (rows[rows.count - 1].indices.isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            rows[rows.count - 1].indices.append(index)
        }
        return rows
    }
}

/// A source by name and kind, as small as the tag the Subscriptions page gives each source.
struct ProxySourceTag: View {
    let source: ProxySource

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(source.name).lineLimit(1)
            Text(source.kindTitle).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(Capsule().fill(Theme.Colors.controlSurface))
    }
}

/// A delay in the colour every list uses: green, orange once slow, red when it timed out.
struct ProxyDelayText: View {
    let delay: ProxyDelay
    /// A dash for a node not tested yet, where delays line up and a gap would read as missing.
    var marksUntested = false

    var body: some View {
        if let label = delay.label {
            Text(label)
                .monospacedDigit()
                .foregroundStyle(delay.color)
        } else if marksUntested {
            Text(verbatim: "—")
                .foregroundStyle(delay.color)
                .accessibilityLabel(Text("Not tested yet"))
        }
    }
}

extension ProxyDelay {
    var color: Color {
        switch self {
        case .untested: Theme.Colors.textTertiary
        case .failed: Theme.Colors.destructive
        case .milliseconds: isSlow ? Theme.Colors.warning : Theme.Colors.success
        }
    }
}

/// A target's colour: its strategy's tint, or the colours Direct and Reject always have.
struct ProxyTargetDot: View {
    let target: ProxyTarget
    let profile: ProxyProfile

    var body: some View {
        Circle()
            .fill(target.color(in: profile))
            .frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
            .accessibilityHidden(true)
    }
}

extension ProxyTarget {
    func color(in profile: ProxyProfile) -> Color {
        switch self {
        case .direct: Theme.Colors.textTertiary
        case .reject: Theme.Colors.destructive
        case .strategy(let id): profile.strategy(id)?.tint.color ?? Theme.Colors.textTertiary
        }
    }
}

/// Sends a route or a rule to any strategy, Direct or Reject; each strategy shows its exit now.
struct ProxyTargetMenu: View {
    let target: ProxyTarget
    let profile: ProxyProfile
    let snapshot: ProxySnapshot?
    let choose: (ProxyTarget) -> Void
    var newStrategy: (() -> Void)?

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { target }, set: { choose($0) })) {
                ProxyTargetOptions(profile: profile, snapshot: snapshot)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if let newStrategy {
                Divider()
                Button("New Strategy…", action: newStrategy)
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                ProxyTargetDot(target: target, profile: profile)
                ProxyTargetName(target: target, profile: profile)
            }
        }
        .fixedSize()
        .accessibilityLabel(Text("Goes to \(target.title(in: profile))"))
    }
}

/// Every target a picker offers: strategies, region ones apart, then Direct and Reject.
struct ProxyTargetOptions: View {
    let profile: ProxyProfile
    let snapshot: ProxySnapshot?

    var body: some View {
        let regional = profile.strategies.filter { $0.soleRegion != nil }
        // Headed, so a strategy named after a region never reads as one of that region's nodes.
        Section("Strategies") {
            ForEach(profile.strategies.filter { $0.soleRegion == nil }, content: option)
        }
        if !regional.isEmpty {
            Section("Region Strategies") {
                ForEach(regional, content: option)
            }
        }
        Section {
            Text("Direct").tag(ProxyTarget.direct)
            Text("Reject").tag(ProxyTarget.reject)
        }
    }

    private func option(_ strategy: ProxyStrategy) -> some View {
        ProxyStrategyOption(strategy: strategy, node: snapshot?.node(reachedBy: strategy.id, in: profile))
            .tag(ProxyTarget.strategy(strategy.id))
    }
}

/// A strategy in a menu: a region's flag first, and its node with that node's delay in a badge.
struct ProxyStrategyOption: View {
    let strategy: ProxyStrategy
    let node: ProxySnapshot.Node?

    var body: some View {
        if let region = strategy.soleRegion {
            Label {
                Text(strategy.bareName)
            } icon: {
                Image(nsImage: ProxyFlagArtwork.menuImage(emoji: region.flagEmoji))
            }
            // A menu's button hides its icon unless asked; a picker's option shows it anyway.
            .labelStyle(.titleAndIcon)
            .badge(badge)
        } else {
            Text(strategy.name).badge(badge)
        }
    }

    private var badge: Text? {
        guard let node else { return nil }
        var parts = [ProxyNodeName(node.name).title]
        if let delay = node.delay(for: strategy.testURL).label { parts.append(delay) }
        return Text(verbatim: parts.joined(separator: " · "))
    }
}

/// A strategy's name; one made by region leads with its region's flag, drawn so Taiwan's shows too.
struct ProxyStrategyName: View {
    let strategy: ProxyStrategy
    /// The surrounding text's point size, which a drawn flag cannot take from the font.
    var size = NSFont.preferredFont(forTextStyle: .callout).pointSize

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let region = strategy.soleRegion { ProxyFlag(emoji: region.flagEmoji, size: size) }
            Text(strategy.bareName).lineLimit(1)
        }
    }
}

/// A target's name, a strategy's as `ProxyStrategyName` shows it.
struct ProxyTargetName: View {
    let target: ProxyTarget
    let profile: ProxyProfile
    var size = NSFont.preferredFont(forTextStyle: .callout).pointSize

    var body: some View {
        if let strategy = target.strategyID.flatMap(profile.strategy) {
            ProxyStrategyName(strategy: strategy, size: size)
        } else {
            Text(target.title(in: profile)).lineLimit(1)
        }
    }
}

extension View {
    /// A switched-off rule, route or source stays editable, so it fades rather than disables.
    func proxyDimmed(_ isDimmed: Bool) -> some View {
        opacity(isDimmed ? 0.55 : 1)
    }
}

extension ProxySnapshot.Node {
    /// The region's flag, which keeps Taiwan's unshown; the name's own only for an unknown region.
    var flag: String? {
        region.map(\.flag) ?? ProxyRegion.leadingFlag(of: name)?.flag
    }

    /// The name without the flag it opens with, which `flag` stands in for.
    var bareName: String {
        ProxyRegion.leadingFlag(of: name)?.rest ?? name
    }

    /// The flag and the short name, as a status line, a menu or a message says where traffic goes.
    var label: String {
        let title = ProxyNodeName(name).title
        return flag.map { "\($0) \(title)" } ?? title
    }

    /// The flag a view draws, Taiwan's included: the region's, else the one the name opens with.
    var flagEmoji: String? {
        region?.flagEmoji ?? ProxyRegion.leadingFlag(of: name)?.flag
    }
}

/// A node as people read it: its flag, its short name, and the provider's note fading after it.
struct ProxyNodeLabel: View {
    let node: ProxySnapshot.Node
    var showsFlag = true
    var showsNote = true
    /// The surrounding text's point size, which a drawn flag cannot take from the font.
    var size = NSFont.preferredFont(forTextStyle: .callout).pointSize

    var body: some View {
        let name = ProxyNodeName(node.name)
        HStack(spacing: Theme.Spacing.xs) {
            if showsFlag, let flag = node.flagEmoji { ProxyFlag(emoji: flag, size: size) }
            Text(name.title).lineLimit(1).layoutPriority(1)
            if showsNote, let note = name.note {
                Text(note).fontWeight(.regular).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

extension ProxyRouteCategory {
    var symbol: String {
        switch self {
        case .ads: return "hand.raised"
        case .lan: return "house"
        case .foreign: return "globe"
        case .china: return "building.2"
        case .apple: return "apple.logo"
        case .telegram: return "paperplane"
        case .icloud: return "icloud"
        case .scholar: return "graduationcap"
        case .chinaBanks: return "building.columns"
        case .crypto: return "bitcoinsign.circle"
        default: break
        }
        let section = ProxyRuleCatalog.Section.allCases.first { $0.categories.contains(self) }
        return section?.symbol ?? "list.bullet"
    }
}

extension ProxyRuleCatalog.Section {
    var symbol: String {
        switch self {
        case .basics: "square.grid.2x2"
        case .ai: "sparkles"
        case .streaming: "play.rectangle"
        case .social: "bubble.left.and.bubble.right"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .platforms: "square.stack.3d.up"
        case .games: "gamecontroller"
        case .mainlandChina: "building.2"
        case .finance: "creditcard"
        }
    }
}

extension ProxyRoute {
    var symbol: String {
        switch kind {
        case .category(let category): category.symbol
        case .custom(_, let ruleSets): ruleSets.contains(where: \.isLinked) ? "link" : "list.bullet"
        }
    }
}
