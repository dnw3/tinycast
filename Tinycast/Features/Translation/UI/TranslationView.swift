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
                    .frame(maxWidth: .infinity, maxHeight: state.isExpanded ? .infinity : nil, alignment: .topLeading)
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
            width: state.isExpanded ? metrics.size.translationPanel.width : metrics.size.translationMiniPanel.width,
            height: state.isExpanded ? metrics.size.translationPanel.height : nil)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.Colors.textPrimary)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.dialog, style: .continuous))
        .panelEntrance()
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSize)
    }

    private var header: some View {
        HStack(spacing: metrics.spacing.md) {
            Label("Translation", systemImage: "translate")
                .font(metrics.typography.panelTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .windowDraggable(true)
            Menu(state.engine.title) {
                Picker("Translation engine", selection: Binding(get: { state.engine }, set: coordinator.changeEngine)) {
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
            .accessibilityLabel("Translation engine")
            .accessibilityValue(state.engine.title)
            .help("Choose Apple or AI translation")
            Button(action: coordinator.togglePinned) {
                SymbolImage(name: state.isPinned ? "pin.fill" : "pin", size: metrics.typography.bodyNSFont.pointSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPinned ? "Unpin Translation" : "Pin Translation")
            .accessibilityValue(state.isPinned ? "Pinned" : "Not pinned")
            .help(state.isPinned ? "Unpin: close when focus leaves" : "Pin: keep open when switching apps")
            Button(action: coordinator.toggleExpanded) {
                SymbolImage(
                    name: state.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    size: metrics.typography.bodyNSFont.pointSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isExpanded ? "Use Mini Window" : "Expand Translation")
            .help(state.isExpanded ? "Use Mini window" : "Expand for longer text")
            Button(action: coordinator.cancel) {
                SymbolImage(name: "xmark", size: metrics.typography.bodyNSFont.pointSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Translation")
            .help("Close (Esc)")
        }
    }

    private var languages: some View {
        HStack(spacing: metrics.spacing.md) {
            languageMenu(
                title: state.sourceOverride.isEmpty ? "Auto · \(sourceName)" : sourceName,
                automatic: "Detect language", action: coordinator.changeSource)
                .accessibilityLabel("Source language")
            SymbolImage(name: "arrow.right", size: metrics.typography.bodyNSFont.pointSize)
                .foregroundStyle(Theme.Colors.textTertiary)
            languageMenu(
                title: (state.targetOverride.isEmpty ? "Auto · " : "")
                    + TranslationLanguageService.name(coordinator.targetLanguage),
                automatic: "Automatic direction", action: coordinator.changeTarget)
                .accessibilityLabel("Target language")
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
            TranslationInputView(
                text: state.input, metrics: metrics, onChange: coordinator.inputChanged,
                onSubmit: coordinator.submit)
                .frame(height: state.isExpanded ? metrics.size.translationInputHeight : metrics.size.translationMiniInputHeight)
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
                Text("Translates automatically · ⇧↵ New line")
                Spacer()
                if state.isExpanded { Text("\(state.input.utf8.count) / 12,000 bytes") }
            }
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}
