import SwiftUI

struct TranslationView: View {
    let onSize: (CGSize) -> Void
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var inputFocused = false
    private var state: TranslationState { coordinator.state }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            header
            languages
            source
            if state.isExpanded || state.phase != .idle || !state.staleOutput.isEmpty {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: Theme.Size.hairline)
                    .accessibilityHidden(true)
                TranslationResultView()
                    .frame(
                        maxWidth: .infinity, maxHeight: state.isExpanded ? .infinity : nil,
                        alignment: .topLeading)
            }
            if let notice = state.resultNotice ?? state.notice?.text {
                HStack(spacing: metrics.spacing.md) {
                    Text(notice)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if state.resultNotice == nil, let action = state.notice?.action {
                        noticeAction(action)
                    }
                }
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
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))
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
            menuButton(.engine, title: state.engine.title)
                .accessibilityLabel(String(localized: "Translation engine"))
                .accessibilityValue(state.engine.title)
                .tooltip(String(localized: "Choose Apple or AI translation"), edge: .bottom)
            HStack(spacing: metrics.spacing.xxs) {
                barAction(
                    state.isPinned ? "pin.fill" : "pin",
                    label: state.isPinned
                        ? String(localized: "Unpin Translation") : String(localized: "Pin Translation"),
                    help: state.isPinned
                        ? String(localized: "Unpin: close when focus leaves")
                        : String(localized: "Pin: keep open when switching apps"),
                    action: coordinator.togglePinned
                )
                .accessibilityValue(
                    state.isPinned ? String(localized: "Pinned") : String(localized: "Not pinned"))
                barAction(
                    state.isExpanded
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: state.isExpanded
                        ? String(localized: "Collapse") : String(localized: "Expand Translation"),
                    help: state.isExpanded
                        ? String(localized: "Collapse") : String(localized: "Expand for longer text"),
                    action: coordinator.toggleExpanded)
                barAction(
                    "xmark", label: String(localized: "Close Translation"),
                    help: String(localized: "Close  ⎋"), action: coordinator.cancel)
            }
            .padding(metrics.spacing.xxs)
            .frosted(in: Capsule())
        }
    }

    private func barAction(
        _ symbol: String, label: String, help: String, action: @escaping () -> Void
    ) -> some View {
        BarButton(isCompact: true, action: action) {
            SymbolImage(name: symbol, size: metrics.typography.bodyNSFont.pointSize)
        }
        .focusable(false)
        .accessibilityLabel(label)
        .tooltip(help, edge: .bottom)
    }

    /// `HeaderMenuButton` speaks through `.help`, which a non-activating panel never shows.
    private func menuButton(_ kind: TranslationMenuKind, title: String) -> some View {
        HeaderMenuButton(
            title: title, icon: .blank, isOpen: coordinator.openMenu == kind, help: "",
            action: { coordinator.toggleMenu(kind) }
        )
        .fixedSize()
        .focusable(false)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            coordinator.menuAnchors[kind] = $0
        }
    }

    private var languages: some View {
        HStack(spacing: metrics.spacing.xs) {
            menuButton(.source, title: sourceTitle)
                .accessibilityLabel(String(localized: "Source language"))
            SymbolImage(name: "arrow.right", size: metrics.typography.bodyNSFont.pointSize)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
            menuButton(
                .target,
                title: state.targetOverride.isEmpty
                    ? String(localized: "Auto · \(TranslationLanguageService.name(coordinator.targetLanguage))")
                    : TranslationLanguageService.name(coordinator.targetLanguage)
            )
            .accessibilityLabel(String(localized: "Target language"))
            Spacer()
        }
    }

    private var sourceTitle: String {
        guard state.sourceOverride.isEmpty else { return TranslationLanguageService.name(state.sourceOverride) }
        guard let detected = state.detectedLanguage else { return String(localized: "Detect language") }
        return String(localized: "Auto · \(TranslationLanguageService.name(detected))")
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
                onSubmit: coordinator.submit, onSelection: { state.selectedInput = $0 },
                onFocusChange: { inputFocused = $0 }
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
            .formFieldChrome(focused: inputFocused)
            if state.origin != .selection || lengthNote != nil {
                HStack(spacing: metrics.spacing.xs) {
                    if state.origin != .selection {
                        textAction(String(localized: "Copy Source"), action: coordinator.copySource)
                        textAction(String(localized: "Translate"), action: coordinator.submit)
                            .disabled(state.isRunning)
                    }
                    Spacer()
                    if let lengthNote {
                        Text(lengthNote)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
    }

    private func noticeAction(_ action: TranslationState.Notice.Action) -> some View {
        switch action {
        case .grantAccessibility:
            textAction(String(localized: "Grant Access…")) { coordinator.perform(action) }
        }
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        BarButton(action: action) {
            Text(title)
                .font(metrics.typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .focusable(false)
    }

    /// Silent until the text nears the request limit; nobody needs a byte count before then.
    private var lengthNote: String? {
        let used = state.requestInput.utf8.count
        guard used * 10 >= TranslationRequest.maximumInputBytes * 8 else { return nil }
        guard state.exceedsLimit else { return String(localized: "Nearly at the length limit") }
        if case .failed = state.phase { return nil }
        return TranslationCoordinator.tooLongMessage
    }
}
