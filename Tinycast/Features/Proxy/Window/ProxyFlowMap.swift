import SwiftUI

/// The overview's map: each kind of traffic, the strategy it goes to, and where that exits now.
struct ProxyFlowMap: View {
    enum Destination {
        case routes
        case strategy(UUID)
    }

    let profile: ProxyProfile
    let mode: ProxyMode
    let snapshot: ProxySnapshot?
    let isConnected: Bool
    var highlight: ProxyFlow.Highlight?
    let open: (Destination) -> Void
    @State private var hovered: Hover?
    /// Each strategy block's width, so its trunk leaves from the block's edge rather than under it.
    @State private var blockWidths: [ProxyTarget: Double] = [:]

    private enum Hover: Equatable {
        case source(ProxyFlow.Source)
        case target(ProxyTarget)
    }

    private static let rowHeight = 27.0
    private static let pillHeight = 23.0
    private static let groupGap = 10.0
    private static let top = 32.0
    private static let targetSpacing = 46.0
    private static let sourceWidth = 176.0
    nonisolated private static let exitWidth = 230.0
    /// Where the strategy column starts, as a share of the width.
    nonisolated private static let strategyColumn = 0.405

    var body: some View {
        let flow = ProxyFlow(profile: profile, mode: mode)
        let layout = flow.layout(
            rowHeight: Self.rowHeight, groupGap: Self.groupGap, top: Self.top, targetSpacing: Self.targetSpacing)
        GeometryReader { geometry in
            let columns = Columns(width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    draw(flow, layout: layout, columns: columns, in: &context)
                }
                header(columns)
                ForEach(Array(zip(flow.rows, layout.rows)), id: \.0.id) { row, y in
                    sourcePill(row)
                        .frame(width: Self.sourceWidth, height: Self.pillHeight)
                        .offset(y: y - Self.pillHeight / 2)
                }
                ForEach(flow.targets, id: \.self) { target in
                    let y = layout.targets[target] ?? 0
                    if target.strategyID != nil {
                        strategyBlock(target)
                            .fixedSize()
                            .frame(height: Self.pillHeight)
                            .onGeometryChange(for: Double.self) { $0.size.width } action: { blockWidths[target] = $0 }
                            .offset(x: columns.strategy, y: y - Self.pillHeight / 2)
                    }
                    exitPill(target)
                        .frame(width: Self.exitWidth - Theme.Spacing.md, height: Self.pillHeight, alignment: .leading)
                        .offset(x: columns.exit, y: y - Self.pillHeight / 2)
                }
            }
        }
        .frame(height: layout.height)
        .opacity(isConnected ? 1 : 0.6)
        .animation(.easeOut(duration: 0.2), value: highlight)
        .accessibilityElement(children: .contain)
    }

    private struct Columns {
        let strategy: Double
        let exit: Double

        init(width: Double) {
            strategy = (width * ProxyFlowMap.strategyColumn).rounded()
            exit = width - ProxyFlowMap.exitWidth
        }
    }

    // MARK: - Lines

    private func draw(
        _ flow: ProxyFlow, layout: ProxyFlow.Layout, columns: Columns, in context: inout GraphicsContext
    ) {
        for (row, y) in zip(flow.rows, layout.rows) {
            for target in row.targets {
                guard let end = layout.targets[target] else { continue }
                let reachesStrategy = target.strategyID != nil
                let x = reachesStrategy ? columns.strategy : columns.exit
                let bend = reachesStrategy ? 70.0 : 150.0
                var path = Path()
                path.move(to: CGPoint(x: Self.sourceWidth, y: y))
                path.addCurve(
                    to: CGPoint(x: x, y: end), control1: CGPoint(x: Self.sourceWidth + bend, y: y),
                    control2: CGPoint(x: x - bend, y: end))
                stroke(path, target: target, lit: isLit(row.source, target), in: &context)
            }
        }
        for target in flow.targets where target.strategyID != nil {
            guard let y = layout.targets[target] else { continue }
            var trunk = Path()
            trunk.move(to: CGPoint(x: columns.strategy + (blockWidths[target] ?? 0), y: y))
            trunk.addLine(to: CGPoint(x: columns.exit, y: y))
            stroke(trunk, target: target, lit: isLit(nil, target), in: &context)
        }
    }

    private func stroke(_ path: Path, target: ProxyTarget, lit: Bool, in context: inout GraphicsContext) {
        let focused = hovered != nil || highlight != nil
        let color = highlight?.failed == true && lit ? Theme.Colors.destructive : target.color(in: profile)
        context.stroke(
            path, with: .color(color.opacity(lit ? 0.85 : focused ? 0.12 : 0.18)),
            lineWidth: lit && focused ? 2.5 : 1.5)
    }

    /// Everything is lit until something is hovered or tested; then only the path that touches.
    private func isLit(_ source: ProxyFlow.Source?, _ target: ProxyTarget) -> Bool {
        switch hovered {
        case .source(let hoveredSource):
            // A block or exit, given no source, lights when the hovered row leads to it.
            guard let source else { return targets(of: hoveredSource).contains(target) }
            return source == hoveredSource
        case .target(let hoveredTarget): return hoveredTarget == target
        case nil: break
        }
        guard let highlight else { return true }
        guard highlight.target == target else { return false }
        return source == nil || highlight.source == nil || highlight.source == source
    }

    private func targets(of source: ProxyFlow.Source) -> [ProxyTarget] {
        ProxyFlow(profile: profile, mode: mode).rows.first { $0.source == source }?.targets ?? []
    }

    private func opacity(source: ProxyFlow.Source) -> Double {
        let lit = targets(of: source).contains { isLit(source, $0) }
        return lit || (hovered == nil && highlight == nil) ? 1 : 0.4
    }

    private func opacity(target: ProxyTarget) -> Double {
        isLit(nil, target) ? 1 : 0.4
    }

    // MARK: - Pills

    private func header(_ columns: Columns) -> some View {
        ZStack(alignment: .topLeading) {
            Text("Traffic").offset(x: Theme.Spacing.md)
            Text("Strategy").offset(x: columns.strategy + Theme.Spacing.xs)
            Text("Exit").offset(x: columns.exit + Theme.Spacing.xs)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .offset(y: Theme.Spacing.md)
        .accessibilityHidden(true)
    }

    private func sourcePill(_ row: ProxyFlow.Row) -> some View {
        let matched = highlight != nil && highlight?.source == row.source
        return Button {
            open(.routes)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                SymbolImage(name: symbol(of: row.source), size: Theme.Size.settingsSidebarGlyph)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.settingsRowIcon)
                Text(title(of: row.source)).lineLimit(1)
                Spacer(minLength: 0)
                if case .rules(let count) = row.source {
                    Text("\(count) rules").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxHeight: .infinity)
            .background(pillShape.fill(Theme.Colors.cardFill))
            .background(pillShape.fill(Theme.Colors.windowSurface))
            .overlay(pillShape.strokeBorder(matched ? Color.accentColor : Theme.Colors.cardStroke,
                                            lineWidth: matched ? 1.5 : 1))
            .contentShape(pillShape)
        }
        .buttonStyle(.plain)
        .opacity(opacity(source: row.source))
        .onHover { hovered = $0 ? .source(row.source) : nil }
        .help(Text("Edit Routing"))
    }

    /// Opaque, so the lines meet its edges instead of running under it.
    private func strategyBlock(_ target: ProxyTarget) -> some View {
        let id = target.strategyID
        let color = target.color(in: profile)
        return Button {
            if let id { open(.strategy(id)) }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
                    .accessibilityHidden(true)
                Text(target.title(in: profile)).lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxHeight: .infinity)
            .background(pillShape.fill(color.opacity(0.14)))
            .background(pillShape.fill(Theme.Colors.windowSurface))
            .overlay(pillShape.strokeBorder(color.opacity(0.55)))
            .contentShape(pillShape)
        }
        .buttonStyle(.plain)
        .opacity(opacity(target: target))
        .onHover { hovered = $0 ? .target(target) : nil }
        .help(Text(blockHelp(id)))
    }

    private func blockHelp(_ id: UUID?) -> String {
        guard let id, let strategy = profile.strategy(id) else { return "" }
        let reach = snapshot?.reach(from: id, in: profile)
        guard let via = reach?.via.first.flatMap(profile.strategy) else { return strategy.kind.title }
        return String(localized: "via \(via.name)")
    }

    private func exitPill(_ target: ProxyTarget) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            exitContent(target)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxHeight: .infinity)
        .background(pillShape.fill(Theme.Colors.cardFill))
        .background(pillShape.fill(Theme.Colors.windowSurface))
        .overlay(pillShape.strokeBorder(Theme.Colors.cardStroke))
        .opacity(opacity(target: target))
        .onHover { hovered = $0 ? .target(target) : nil }
    }

    @ViewBuilder
    private func exitContent(_ target: ProxyTarget) -> some View {
        switch target {
        case .direct:
            exitLine(symbol: "arrow.right", title: ProxyTarget.direct.title(in: profile),
                     detail: ProxyTarget.directSubtitle)
        case .reject:
            exitLine(symbol: "nosign", title: ProxyTarget.reject.title(in: profile),
                     detail: ProxyTarget.rejectSubtitle)
        case .strategy(let id):
            let tested = highlight?.target == target ? highlight?.exit.flatMap { snapshot?.nodes[$0] } : nil
            let reach = snapshot?.reach(from: id, in: profile)
            if highlight?.target == target, highlight?.failed == true {
                exitLine(symbol: "exclamationmark.triangle", title: String(localized: "Could not connect"),
                         detail: nil)
            } else if let node = tested ?? reach?.node {
                ProxyNodeLabel(node: node, showsNote: false, size: NSFont.systemFontSize)
                ProxyDelayText(delay: node.delay(for: profile.strategy(id)?.testURL)).font(.caption)
            } else if let outcome = reach?.outcome {
                exitLine(symbol: outcome == .direct ? "arrow.right" : "nosign",
                         title: outcome.title(in: profile), detail: nil)
            } else {
                Text(isConnected ? "No node picked" : "Connect to see the exit")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func exitLine(symbol: String, title: String, detail: String?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            SymbolImage(name: symbol, size: Theme.Size.settingsSidebarGlyph).foregroundStyle(.secondary)
            Text(title).lineLimit(1)
            if let detail { Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
        }
    }

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
    }

    private func title(of source: ProxyFlow.Source) -> String {
        switch source {
        case .rules: String(localized: "My Rules")
        case .route(let id) where id == ProxyRoute.finalID: ProxyRoute.finalTitle
        case .route(let id): profile.routes.first { $0.id == id }?.title ?? id
        }
    }

    private func symbol(of source: ProxyFlow.Source) -> String {
        switch source {
        case .rules: "person"
        case .route(let id) where id == ProxyRoute.finalID: "ellipsis"
        case .route(let id): profile.routes.first { $0.id == id }?.symbol ?? "list.bullet"
        }
    }
}
