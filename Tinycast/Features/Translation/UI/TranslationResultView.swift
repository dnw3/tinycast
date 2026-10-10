import SwiftUI

struct TranslationResultView: View {
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var contentHeight: CGFloat = 0
    private var state: TranslationState { coordinator.state }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            toolbar
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: state.isExpanded ? nil : min(contentHeight, metrics.size.translationMiniResultHeight))
        }
    }

    private var toolbar: some View {
        HStack(spacing: metrics.spacing.md) {
            if state.isRunning { ProgressView().controlSize(.small) }
            Text(state.isRunning ? (state.phase == .detecting ? "Detecting language…" : "Translating…") : "Result")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Button(action: coordinator.copy) {
                SymbolImage(name: state.isCopied ? "checkmark" : "doc.on.doc", size: metrics.typography.bodyNSFont.pointSize)
            }
            .buttonStyle(.accessoryBar)
            .disabled(!state.canCopy)
            .accessibilityLabel(state.isCopied ? "Translation copied" : "Copy translation")
            .help(state.isCopied ? "Translation copied" : "Copy translation (⌘⇧C)")
            Menu {
                Button("Translate Again", systemImage: "arrow.clockwise", action: coordinator.submit)
                    .disabled(!state.canSubmit || state.isRunning || state.isDelivering)
                if state.origin == .selection {
                    Divider()
                    Button(state.deliveryTitle ?? "Replace selection", systemImage: "text.insert", action: coordinator.deliver)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!coordinator.canDeliver)
                }
            } label: {
                SymbolImage(name: "ellipsis", size: metrics.typography.bodyNSFont.pointSize)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.accessoryBar)
            .accessibilityLabel("Translation actions")
            .help(state.origin == .selection
                ? "Translation actions · Apply to original field (⌘Return)" : "Translation actions")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            Text("Your translation will appear here.")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textTertiary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(metrics.typography.rowTitle)
                if state.needsLanguages {
                    Button("Open Language & Region", action: coordinator.openLanguageSettings)
                        .buttonStyle(.modalAction(.standard, fillsWidth: false))
                } else if state.engine == .ai {
                    Button("Translation Settings…", action: coordinator.showSettings)
                        .buttonStyle(.modalAction(.standard, fillsWidth: false))
                }
            }
        case .detecting, .translating, .finished:
            if !state.output.isEmpty {
                Text(state.output)
                    .font(metrics.typography.rowTitle)
                    .lineSpacing(metrics.spacing.xs)
                    .textSelection(.enabled)
            }
        }
    }
}
