import Foundation

struct CaptureNumberFormat: Codable, Equatable, Sendable {
    enum Style: String, Codable, CaseIterable, Sendable {
        case decimal, roman, uppercase, lowercase
        var title: String {
            switch self {
            case .decimal: "1, 2, 3"
            case .roman: "I, II, III"
            case .uppercase: "A, B, C"
            case .lowercase: "a, b, c"
            }
        }
    }

    var style: Style = .decimal
    var value = 1
    var isValid: Bool { (1...3999).contains(value) }

    var label: String {
        guard isValid else { return "" }
        switch style {
        case .decimal: return String(value)
        case .roman:
            var remainder = value, result = ""
            for (number, symbol) in [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"),
                (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
                while remainder >= number { result += symbol; remainder -= number }
            }
            return result
        case .uppercase, .lowercase:
            let letters = Array(style == .uppercase ? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "abcdefghijklmnopqrstuvwxyz")
            var remainder = value, result = ""
            while remainder > 0 {
                remainder -= 1
                result.insert(letters[remainder % 26], at: result.startIndex)
                remainder /= 26
            }
            return result
        }
    }
}
