import Foundation

struct TranslationPreferences: Codable, Equatable, Sendable {
    enum Engine: String, Codable, CaseIterable, Sendable {
        case apple
        case ai

        var title: String { self == .apple ? "Apple" : "AI" }
    }

    var firstLanguage = "zh-Hans"
    var secondLanguage = "en"
    var engine: Engine = .apple
}
