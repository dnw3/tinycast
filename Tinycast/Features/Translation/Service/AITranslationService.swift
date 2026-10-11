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
        return try await response(input, provider: provider, onDelta: onDelta)
    }

    @MainActor
    static func translate(
        _ request: TranslationBatchRequest, provider: any AIProvider
    ) async throws -> [String] {
        let input = AIRequest(
            instructions: request.instructions,
            messages: [AIMessage(role: .user, text: try request.encoded())],
            maxOutputTokens: TranslationRequest.maximumOutputTokens)
        return try request.decoded(await response(input, provider: provider) { _ in })
    }

    @MainActor
    private static func response(
        _ input: AIRequest, provider: any AIProvider, onDelta: @MainActor (String) -> Void
    ) async throws -> String {
        var output = ""
        var finished = false
        for try await event in provider.stream(input) {
            try Task.checkCancellation()
            switch event {
            case .text(let delta):
                output += delta
                guard output.utf8.count <= 96_000 else {
                    throw TranslationBatchRequest.Failure.invalidResponse
                }
                onDelta(delta)
            case .finished:
                finished = true
            case .toolCallRequested:
                throw AIProviderError.responseFailed(
                    String(localized: "Translation cannot run tools. Choose another model."))
            default: break
            }
        }
        try Task.checkCancellation()
        guard finished else {
            throw AIProviderError.responseFailed(
                String(localized: "The translation ended early. Retry before replacing text."))
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.responseFailed(
                String(localized: "The model returned no translation. Try again or choose another model."))
        }
        return output
    }
}
