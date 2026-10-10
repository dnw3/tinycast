import Foundation
import NaturalLanguage
import Translation

enum TranslationLanguageService {
    nonisolated static func detect(_ text: String, preferred: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = Dictionary(
            uniqueKeysWithValues: recognizer.languageHypotheses(withMaximum: 5).map {
                ($0.key.rawValue, $0.value)
            })
        return TranslationLanguagePolicy.detect(text, hypotheses: hypotheses, preferred: preferred)
    }

    static func languages() async -> [String] {
        let supported = await LanguageAvailability().supportedLanguages.map { language in
            guard language.languageCode?.identifier == "zh" else { return language.minimalIdentifier }
            return language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        let common = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "pt", "ru"]
        return Array(Set(supported + common)).sorted { name($0) < name($1) }
    }

    static func name(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
