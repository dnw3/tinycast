import Foundation

enum CaptureRedactionPolicy: String, CaseIterable, Sendable {
    case personalInfo, allText, faces, people

    var title: String {
        switch self {
        case .personalInfo: "Find Personal Information"
        case .allText: "Find All Text"
        case .faces: "Find Faces"
        case .people: "Find People"
        }
    }

    var content: TextRecognitionResult.Content {
        switch self {
        case .personalInfo, .allText: .text
        case .faces: .faces
        case .people: .people
        }
    }

    func candidates(in boxes: [(text: String, rect: CGRect)], bounds: CGRect) -> [Candidate] {
        boxes.compactMap { box in
            guard CaptureGeometry.valid(box.rect), self != .personalInfo || Self.isPersonalInformation(box.text) else {
                return nil
            }
            let padding = self == .faces ? max(3, min(box.rect.width, box.rect.height) * 0.1) : 3
            let rect = box.rect.insetBy(dx: -padding, dy: -padding).integral.intersection(bounds)
            guard CaptureGeometry.valid(rect) else { return nil }
            return Candidate(rect: rect, label: box.text, included: true)
        }
    }

    struct Candidate: Equatable, Sendable {
        let rect: CGRect
        let label: String
        var included: Bool
    }

    private static func isPersonalInformation(_ text: String) -> Bool {
        let patterns = [
            #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            #"(?<![0-9])(?:\+?86[ -]?)?1[3-9][0-9]{9}(?![0-9])"#,
            #"(?<![0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}(?![0-9])"#
        ]
        if patterns.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
            return true
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue),
            detector.firstMatch(in: text, range: range) != nil { return true }
        guard let expression = try? NSRegularExpression(pattern: #"(?<![0-9])(?:[0-9][ -]?){12,18}[0-9](?![0-9])"#)
        else { return false }
        return expression.matches(in: text, range: range).contains { match in
            guard let range = Range(match.range, in: text) else { return false }
            let digits = text[range].compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
            let sum = digits.reversed().enumerated().reduce(0) { total, item in
                let value = item.offset.isMultiple(of: 2) ? item.element : item.element * 2
                return total + (value > 9 ? value - 9 : value)
            }
            return sum.isMultiple(of: 10)
        }
    }
}
