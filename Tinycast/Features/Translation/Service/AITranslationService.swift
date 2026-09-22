import Foundation

enum AITranslationService {
    @MainActor
    static func translate(
        _ request: TranslationRequest, provider: any AIProvider,
        onDelta: @MainActor (String) -> Void
    ) async throws -> String {
        let input = AIRequest(
            instructions: request.instructions,
            messages: [AIMessage(role: .user, text: request.text)],
            maxOutputTokens: TranslationRequest.maximumOutputTokens)
        var output = ""
        var finished = false
        for try await event in provider.stream(input) {
            try Task.checkCancellation()
            switch event {
            case .text(let delta):
                output += delta
                onDelta(delta)
            case .finished:
                finished = true
            case .toolCallRequested:
                throw AIProviderError.responseFailed("Translation cannot run tools. Choose another model.")
            default: break
            }
        }
        try Task.checkCancellation()
        guard finished else {
            throw AIProviderError.responseFailed("The translation ended early. Retry before replacing text.")
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.responseFailed("The model returned no translation. Try again or choose another model.")
        }
        return output
    }
}
