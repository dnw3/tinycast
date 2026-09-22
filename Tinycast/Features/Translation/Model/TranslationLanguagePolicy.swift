import Foundation

enum TranslationLanguagePolicy {
    static func family(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
    }

    static func target(source: String, first: String, second: String, override: String) -> String {
        guard override.isEmpty else { return override }
        return family(source) == family(first) ? second : first
    }

    static func hasLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    static func detect(
        _ text: String, hypotheses: [String: Double], preferred: [String]
    ) -> String? {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return nil }
        if letters.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "ja" }
        if letters.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return "ko" }
        let hanCount = letters.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let latinWords = text.split { !$0.isASCII || !$0.isLetter }.count
        if hanCount > 0, hanCount >= latinWords {
            return (hypotheses["zh-Hant"] ?? 0) > (hypotheses["zh-Hans"] ?? 0) + 0.25
                ? "zh-Hant" : "zh-Hans"
        }
        let ranked = hypotheses.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        guard let best = ranked.first else { return nil }
        let isLatin = letters.allSatisfy { $0.isASCII }
        let prefersEnglish = preferred.contains { family($0) == "en" }
        if isLatin, prefersEnglish, text.count <= 12,
            best.value < 0.5, (hypotheses["en"] ?? 0) >= 0.1
        { return "en" }
        if best.value < 0.6 {
            for language in preferred {
                if let candidate = ranked.first(where: { family($0.key) == family(language) }),
                    candidate.value >= best.value - 0.15
                { return candidate.key }
            }
        }
        return best.key
    }
}
