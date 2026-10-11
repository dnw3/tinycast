import SwiftUI

struct CaptureTranslationReview: View {
    let state: CaptureEditorState
    @Bindable var review: CaptureTranslationReviewState
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    private var languages: [String] {
        Array(Set(coordinator.translationLanguages + [review.source, review.translation.target])).filter {
            !$0.isEmpty
        }.sorted()
    }

    var body: some View {
        if review.translation.blocks.indices.contains(review.index) {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                CaptureToolFlow(spacing: metrics.spacing.md) {
                    Picker("From", selection: $review.source) {
                        if review.source.isEmpty { Text("Choose Language").tag("") }
                        ForEach(languages, id: \.self) { Text(TranslationLanguageService.name($0)).tag($0) }
                    }.fixedSize()
                    Picker("To", selection: $review.translation.target) {
                        ForEach(languages, id: \.self) { Text(TranslationLanguageService.name($0)).tag($0) }
                    }.fixedSize()
                    Picker("Engine", selection: $review.engine) {
                        ForEach(TranslationPreferences.Engine.allCases, id: \.self) {
                            Text(LocalizedStringKey($0.title)).tag($0)
                        }
                    }.fixedSize()
                    Button("Translate Paragraphs") { coordinator.translateImageParagraphs() }
                        .disabled(review.source.isEmpty)
                    if review.needsLanguages {
                        Button("Translation Languages…") { coordinator.openTranslationLanguages() }
                    }
                    CaptureIconButton(
                        title: state.document.edit.translation?.enabled == false
                            ? String(localized: "Show Translation") : String(localized: "Show Original"),
                        symbol: "text.below.photo",
                        selected: state.document.edit.translation?.enabled == false
                    ) {
                        coordinator.showOriginalText()
                    }.disabled(state.document.edit.translation == nil)
                    CaptureIconButton(title: String(localized: "Close Translation"), symbol: "xmark") {
                        state.translationReview = nil
                    }
                }
                HStack(alignment: .top, spacing: metrics.spacing.md) {
                    Text(review.translation.blocks[review.index].source).lineLimit(3).textSelection(.enabled)
                        .foregroundStyle(Theme.Colors.textSecondary).frame(
                            maxWidth: .infinity, alignment: .leading)
                    TextField(
                        "Translation", text: $review.translation.blocks[review.index].text, axis: .vertical
                    )
                    .lineLimit(2...3).textFieldStyle(.plain).accessibilityLabel(
                        String(localized: "Paragraph Translation")
                    )
                    .padding(metrics.spacing.sm).background(
                        Theme.Colors.panelScrim,
                        in: RoundedRectangle(cornerRadius: metrics.radius.barControl)
                    )
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: metrics.spacing.sm) {
                    Toggle("Include Paragraph", isOn: $review.translation.blocks[review.index].included)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Text("\(review.index + 1)/\(review.translation.blocks.count)").monospacedDigit()
                    CaptureIconButton(title: String(localized: "Previous Paragraph"), symbol: "chevron.left")
                    {
                        review.index =
                            (review.index + review.translation.blocks.count - 1)
                            % review.translation.blocks.count
                    }
                    CaptureIconButton(title: String(localized: "Next Paragraph"), symbol: "chevron.right") {
                        review.index = (review.index + 1) % review.translation.blocks.count
                    }
                    Button("Apply Edits") { coordinator.applyImageTranslation() }
                        .disabled(
                            !review.translation.isValid
                                || review.translation == state.document.edit.translation)
                }
            }
            .font(metrics.typography.bar).disabled(state.busy)
            .onChange(of: review.translation.target) { _, _ in clearOutput() }
            .onChange(of: review.source) { _, _ in clearOutput() }
        }
    }

    private func clearOutput() {
        for index in review.translation.blocks.indices { review.translation.blocks[index].text = "" }
    }
}
