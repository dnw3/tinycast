import Foundation

extension TranslationBatchRequest.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidInput: String(localized: "Translate up to 32 paragraphs and 12 KB at a time. Select a smaller region.")
        case .invalidResponse: String(localized: "The translation did not preserve every paragraph. Retry before applying it to the image.")
        }
    }
}
