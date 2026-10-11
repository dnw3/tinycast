import Foundation

struct CapturePresentationPreset: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var presentation: CapturePresentation

    enum BuiltIn: String, CaseIterable, Sendable {
        case gradient, paper, grid, window

        var title: String {
            switch self {
            case .gradient: "Gradient"
            case .paper: "Paper"
            case .grid: "Grid"
            case .window: "Window"
            }
        }

        var presentation: CapturePresentation {
            switch self {
            case .gradient: .init()
            case .paper: .init(background: .solid, color: .init(red: 242, green: 240, blue: 234),
                padding: 40, radius: 12, shadow: 12)
            case .grid: .init(background: .grid, color: .init(red: 238, green: 243, blue: 250),
                secondary: .init(red: 208, green: 220, blue: 237), padding: 48, radius: 12, shadow: 12)
            case .window: .init(padding: 64, radius: 12, shadow: 24, windowFrame: true)
            }
        }
    }

    enum Failure: Error {
        case name, style, limit, duplicate, missing

    }

    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == name && (1...40).contains(name.count) && name.utf8.count <= 160
            && !name.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
            }
            && presentation.isValid
    }

    static func valid(_ presets: [Self]) -> Bool {
        presets.count <= 20 && presets.allSatisfy(\.isValid)
            && Set(presets.map(\.id)).count == presets.count
            && Set(presets.map { $0.name.precomposedStringWithCanonicalMapping.lowercased() }).count == presets.count
    }
}
