import Foundation

enum CaptureKeystrokePolicy {
    static func label(
        mode: CaptureRecordingOptions.Keys, keyCode: UInt16, characters: String?,
        command: Bool, control: Bool, option: Bool, shift: Bool, repeated: Bool, secure: Bool
    ) -> String? {
        guard mode != .off, !secure, !repeated,
            mode == .all || command || control || option else { return nil }
        let name: String
        switch keyCode {
        case 36: name = "↩"
        case 48: name = "⇥"
        case 49: name = "Space"
        case 51: name = "⌫"
        case 53: name = "Esc"
        case 117: name = "⌦"
        case 123: name = "←"
        case 124: name = "→"
        case 125: name = "↓"
        case 126: name = "↑"
        default:
            guard let characters, !characters.isEmpty, characters.count <= 4,
                !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { return nil }
            name = characters.uppercased()
        }
        return [(control ? "⌃" : ""), (option ? "⌥" : ""), (shift ? "⇧" : ""),
            (command ? "⌘" : ""), name].joined()
    }
}
