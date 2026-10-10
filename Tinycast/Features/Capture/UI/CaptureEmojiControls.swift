import SwiftUI

struct CaptureEmojiControls: View {
    @Bindable var state: CaptureEditorState
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var query = ""

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            TextField("Search emoji", text: $query)
                .frame(width: metrics.scaled(Theme.Size.captureAdjustmentWidth))
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal) {
                LazyHStack(spacing: metrics.spacing.xxs) {
                    ForEach(coordinator.emojiSuggestions(query)) { entry in
                        let glyph = coordinator.emojiGlyph(entry)
                        Button {
                            state.emoji = glyph
                            state.updateSelectedStyle()
                        } label: {
                            Text(glyph).font(.system(size: metrics.scaled(Theme.Size.captureGlyph)))
                                .frame(width: metrics.scaled(Theme.Size.captureTool),
                                    height: metrics.scaled(Theme.Size.captureTool))
                                .background(state.emoji == glyph ? Theme.Colors.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: metrics.radius.barControl))
                        }.buttonStyle(.borderless).focusable(false).accessibilityLabel(entry.displayName)
                            .tooltip(entry.displayName)
                    }
                }
            }.scrollIndicators(.hidden)
                .frame(height: metrics.scaled(Theme.Size.captureTool))
            Picker("Size", selection: Binding(get: { state.emojiSize }, set: {
                state.emojiSize = $0
                state.updateSelectedStyle()
            })) {
                ForEach([24.0, 48, 64, 96, 128], id: \.self) { Text("\(Int($0)) px").tag($0) }
                if ![24.0, 48, 64, 96, 128].contains(state.emojiSize) {
                    Text("\(Int(state.emojiSize)) px").tag(state.emojiSize)
                }
            }.fixedSize()
        }
        .disabled(state.busy)
        .task { await coordinator.loadEmoji() }
    }
}

extension CaptureCoordinator {
    func loadEmoji() async {
        if !core.emojiIndex.isLoaded { await core.emojiIndex.load() }
    }

    func emojiSuggestions(_ query: String) -> [EmojiEntry] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(core.emojiIndex.entries.prefix(64))
        }
        return core.emojiIndex.search(query, frequent: core.frequentEmoji, limit: 64)
    }

    func emojiGlyph(_ entry: EmojiEntry) -> String { entry.display(tone: core.settings.emojiSkinTone) }
}
