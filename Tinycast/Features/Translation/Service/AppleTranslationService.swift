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
        let status = await LanguageAvailability().status(from: source, to: target)
        try Task.checkCancellation()
        switch status {
        case .installed: break
        case .supported: throw Failure.needsLanguages
        case .unsupported: throw Failure.unsupported
        @unknown default: throw Failure.unsupported
        }
        let session = TranslationSession(installedSource: source, target: target)
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
}
