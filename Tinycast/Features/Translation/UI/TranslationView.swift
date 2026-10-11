import SwiftUI

struct TranslationView: View {
    let onSize: (CGSize) -> Void
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    private var state: TranslationState { coordinator.state }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            header
            languages
            source
            if state.isExpanded || state.phase != .idle {
                Divider()
                TranslationResultView()
                    .frame(
                        maxWidth: .infinity, maxHeight: state.isExpanded ? .infinity : nil,
                        alignment: .topLeading)
            }
            if let notice = state.notice {
                Text(notice)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(state.isExpanded ? metrics.spacing.xxl : metrics.spacing.xl)
        .frame(
            width: state.isExpanded
                ? metrics.size.translationPanel.width : metrics.size.translationMiniPanel.width,
            height: state.isExpanded ? metrics.size.translationPanel.height : nil
        )
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.Colors.textPrimary)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.dialog, style: .continuous))
        .panelEntrance()
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSize)
    }

    private var header: some View {
        HStack(spacing: metrics.spacing.md) {
            Label(
                state.origin == .selection
                    ? String(localized: "Translation") : String(localized: "Screenshot Text"),
                systemImage: "translate"
            )
            .font(metrics.typography.panelTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .windowDraggable(true)
            Menu(state.engine.title) {
                Picker(
                    "Translation engine",
                    selection: Binding(get: { state.engine }, set: coordinator.changeEngine)
                ) {
                    ForEach(TranslationPreferences.Engine.allCases, id: \.self) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Translation Settings…") { coordinator.showSettings() }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .font(metrics.typography.bar)
            .accessibilityLabel(String(localized: "Translation engine"))
            .accessibilityValue(state.engine.title)
            .help(String(localized: "Choose Apple or AI translation"))
            if state.origin == .selection {
                Button(action: coordinator.togglePinned) {
                    Image(systemName: state.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    state.isPinned
                        ? String(localized: "Unpin Translation") : String(localized: "Pin Translation")
                )
                .accessibilityValue(state.isPinned ? String(localized: "Pinned") : String(localized: "Not pinned"))
                .help(
                    state.isPinned
                        ? String(localized: "Unpin: close when focus leaves")
                        : String(localized: "Pin: keep open when switching apps"))
            }
            Button(action: coordinator.toggleExpanded) {
                Image(
                    systemName: state.isExpanded
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                state.isExpanded
                    ? String(localized: "Use Mini Window") : String(localized: "Expand Translation")
            )
            .help(
                state.isExpanded
                    ? String(localized: "Use Mini window") : String(localized: "Expand for longer text"))
            Button(action: coordinator.cancel) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close Translation"))
                .help(String(localized: "Close (Esc)"))
        }
    }

    private var languages: some View {
        HStack(spacing: metrics.spacing.md) {
            languageMenu(
                title: state.sourceOverride.isEmpty ? String(localized: "Auto · \(sourceName)") : sourceName,
                automatic: String(localized: "Detect language"), action: coordinator.changeSource
            )
            .accessibilityLabel(String(localized: "Source language"))
            Image(systemName: "arrow.right").foregroundStyle(Theme.Colors.textTertiary)
            languageMenu(
                title: state.targetOverride.isEmpty
                    ? String(localized: "Auto · \(TranslationLanguageService.name(coordinator.targetLanguage))")
                    : TranslationLanguageService.name(coordinator.targetLanguage),
                automatic: String(localized: "Automatic direction"), action: coordinator.changeTarget
            )
            .accessibilityLabel(String(localized: "Target language"))
            Spacer()
        }
    }

    private var sourceName: String {
        state.source.map(TranslationLanguageService.name) ?? "Detect"
    }

    private func languageMenu(
        title: String, automatic: String, action: @escaping (String) -> Void
    ) -> some View {
        Menu(title) {
            Button(automatic) { action("") }
            Divider()
            ForEach(coordinator.languages, id: \.self) { language in
                Button(TranslationLanguageService.name(language)) { action(language) }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .font(metrics.typography.bar)
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            if let preview = coordinator.sourcePreview {
                Image(decorative: preview, scale: 1).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: metrics.size.rowIcon * 2, alignment: .leading)
                    .accessibilityLabel(String(localized: "Source screenshot with current annotations"))
            }
            TranslationInputView(
                text: state.input, metrics: metrics, onChange: coordinator.inputChanged,
                onSubmit: coordinator.submit, onSelection: { state.selectedInput = $0 }
            )
            .frame(
                height: state.isExpanded
                    ? metrics.size.translationInputHeight : metrics.size.translationMiniInputHeight
            )
            .overlay(alignment: .topLeading) {
                if state.input.isEmpty {
                    Text("Type or paste text…")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(metrics.spacing.md)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.Colors.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row))
            HStack {
                if state.origin == .selection {
                    Text("Translates automatically · ⇧↵ New line")
                } else {
                    Button("Copy Source", action: coordinator.copySource)
                    Button("Translate", action: coordinator.submit)
                }
                Spacer()
                if state.isExpanded { Text("\(state.input.utf8.count) / 12,000 bytes") }
            }
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}
