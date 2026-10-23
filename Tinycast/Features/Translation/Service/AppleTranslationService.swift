import Foundation
import Translation

enum AppleTranslationService {
    enum Failure: LocalizedError, Equatable {
        case needsLanguages
        case unsupported

        var errorDescription: String? {
            switch self {
            case .needsLanguages:
                String(
                    localized:
                        "Download the source and target languages in System Settings › Language & Region › Translation Languages."
                )
            case .unsupported:
                String(
                    localized:
                        "Apple does not support this language pair. Choose another language or the AI engine."
                )
            }
        }
    }

    static func translate(_ request: TranslationRequest) async throws -> String {
        let results = try await translate(
            TranslationBatchRequest(
                texts: [request.text], source: request.source, target: request.target))
        return results[0]
    }

    static func translate(_ request: TranslationBatchRequest) async throws -> [String] {
        guard request.isValid else { throw TranslationBatchRequest.Failure.invalidInput }
        let source = Locale.Language(identifier: request.source)
        let target = Locale.Language(identifier: request.target)
        if source.isEquivalent(to: target) { return request.texts }
        let pair = try await installedPair(from: source, to: target)
        try Task.checkCancellation()
        let session = TranslationSession(installedSource: pair.source, target: pair.target)
        let result = try await session.translations(
            from: request.texts.enumerated().map {
                .init(sourceText: $0.element, clientIdentifier: String($0.offset))
            })
        try Task.checkCancellation()
        let items = result.compactMap { response -> TranslationBatchRequest.Item? in
            guard let identifier = response.clientIdentifier, let id = Int(identifier) else { return nil }
            return .init(id: id, text: response.targetText)
        }
        return try request.validated(items)
    }

    /// A download is a locale, so the region a bare code resolves to can miss the one installed.
    private static func installedPair(
        from source: Locale.Language, to target: Locale.Language
    ) async throws -> (source: Locale.Language, target: Locale.Language) {
        let availability = LanguageAvailability()
        switch await availability.status(from: source, to: target) {
        case .installed: return (source, target)
        case .supported: break
        case .unsupported: throw Failure.unsupported
        @unknown default: throw Failure.unsupported
        }
        let supported = await availability.supportedLanguages
        for candidate in variants(of: source, among: supported) {
            for destination in variants(of: target, among: supported) {
                if await availability.status(from: candidate, to: destination) == .installed {
                    return (candidate, destination)
                }
            }
        }
        throw Failure.needsLanguages
    }

    /// Region may move, since one English is another's asset, but a different script is a language.
    private static func variants(
        of language: Locale.Language, among supported: [Locale.Language]
    ) -> [Locale.Language] {
        [language]
            + supported.filter {
                $0.languageCode == language.languageCode && $0.script == language.script
                    && !$0.isEquivalent(to: language)
            }
    }
}
