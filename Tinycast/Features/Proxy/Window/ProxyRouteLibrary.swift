import SwiftUI

/// Adds routes: a service or category from the library, any catalog set by name, or a link.
struct ProxyRouteLibrary: View {
    @Environment(AppCore.self) private var core
    let manager: ProxyManager
    let openLink: (String) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var target: ProxyTarget

    private static let size = CGSize(width: 600, height: 640)
    private static let catalogResults = 30

    init(manager: ProxyManager, openLink: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.manager = manager
        self.openLink = openLink
        self.close = close
        _target = State(initialValue: .strategy(manager.store.profile.defaultStrategy))
    }

    private var profile: ProxyProfile { manager.store.profile }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "Add Route",
                subtitle: "Pick a service or a category, type a geosite or geoip name, or paste a rule-set link."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.md) {
                TextField("Search", text: $query, prompt: Text("Netflix, Games, geosite:openai or a link"))
                    .textFieldStyle(.roundedBorder)
                ProxyTargetPicker(
                    title: String(localized: "Goes to"), target: $target, profile: profile,
                    snapshot: manager.snapshot)
                    .fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.md)

            Form {
                if let link {
                    Section {
                        row(
                            symbol: "link", title: String(localized: "Add from Link"), subtitle: link, isAdded: false
                        ) {
                            openLink(link)
                        }
                    }
                }
                ForEach(sections, id: \.section) { section, categories in
                    Section {
                        ForEach(categories, id: \.self) { category in
                            row(
                                symbol: category.symbol, title: category.title,
                                subtitle: category.summary ?? category.ruleSets.map(\.catalogName).joined(separator: " · "),
                                isAdded: profile.routes.contains { $0.id == category.rawValue }
                            ) {
                                add(.category(category, to: target))
                            }
                        }
                    } header: {
                        Text(section.title)
                    }
                }
                if !catalogSets.isEmpty {
                    Section {
                        ForEach(catalogSets, id: \.name) { ruleSet in
                            row(
                                symbol: "list.bullet", title: ruleSet.catalogName,
                                subtitle: ruleSet.behavior == .ipcidr
                                    ? String(localized: "Address ranges from the catalog")
                                    : String(localized: "Domains from the catalog"),
                                isAdded: profile.routes.contains { $0.ruleSets.map(\.name) == [ruleSet.name] && !$0.isBuiltIn }
                            ) {
                                add(ProxyRoute(
                                    id: ProxyRoute.newCustomID(), kind: .custom(name: ruleSet.catalogName, ruleSets: [ruleSet]),
                                    target: target, isEnabled: true))
                            }
                        }
                    } header: {
                        Text("Rule Set Catalog")
                    } footer: {
                        Text("Every geosite and geoip set in MetaCubeX/meta-rules-dat, updated daily by the core.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if sections.isEmpty, catalogSets.isEmpty, link == nil {
                    Text("Nothing matches. Try another name, or paste a rule-set link.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Text("A new route goes ahead of any route that would match its traffic first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .settingsEditorPanelSurface()
    }

    private var link: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return ProxyText.isWebURL(trimmed) ? ProxyRuleSetDetection.normalize(trimmed) : nil
    }

    private var sections: [(section: ProxyRuleCatalog.Section, categories: [ProxyRouteCategory])] {
        guard link == nil else { return [] }
        let found = Set(ProxyRuleCatalog.categories(matching: query) { $0.title })
        return ProxyRuleCatalog.Section.allCases.compactMap { section in
            let categories = section.categories.filter(found.contains)
            return categories.isEmpty ? nil : (section, categories)
        }
    }

    private var catalogSets: [ProxyRuleSet] {
        guard link == nil else { return [] }
        return ProxyRuleCatalog.ruleSets(matching: query, limit: Self.catalogResults)
    }

    private func row(
        symbol: String, title: String, subtitle: String, isAdded: Bool, add: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: symbol, size: Theme.Size.settingsSidebarGlyph)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if isAdded {
                Text("Added").foregroundStyle(.secondary)
            } else {
                Button("Add", action: add)
            }
        }
    }

    private func add(_ route: ProxyRoute) {
        guard core.proxyCoordinator.update({ $0.addRoute(route) }) else { return }
        core.showMessage(String(localized: "Added “\(route.title)”"), tone: .success)
    }
}

extension ProxyRoute {
    /// `custom-` and eight hex digits, stable across renames.
    static func newCustomID() -> String {
        "custom-" + UUID().uuidString.prefix(8).lowercased()
    }
}
