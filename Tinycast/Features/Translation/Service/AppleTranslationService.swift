import Foundation
import Translation

enum AppleTranslationService {
    enum Failure: LocalizedError, Equatable {
        case needsLanguages
        case unsupported

        var errorDescription: String? {
            switch self {
            case .needsLanguages:
                "Download the source and target languages in System Settings → Language & Region → Translation Languages."
            case .unsupported:
                "Apple does not support this language pair. Choose another language or the AI engine."
            }
        }
    }

    static func translate(_ request: TranslationRequest) async throws -> String {
        let source = Locale.Language(identifier: request.source)
        let target = Locale.Language(identifier: request.target)
        if source.isEquivalent(to: target) { return request.text }
        let status = await LanguageAvailability().status(from: source, to: target)
        try Task.checkCancellation()
        switch status {
        case .installed: break
        case .supported: throw Failure.needsLanguages
        case .unsupported: throw Failure.unsupported
        @unknown default: throw Failure.unsupported
        }
        let session = TranslationSession(installedSource: source, target: target)
        let result = try await session.translate(request.text)
        try Task.checkCancellation()
        return result.targetText
    }
}
