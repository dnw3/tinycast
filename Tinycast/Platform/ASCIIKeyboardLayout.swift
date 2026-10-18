import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ASCIIKeyboardLayout {
    /// No modifiers by default: the key's base character, which is what a shortcut glyph shows.
    @MainActor static func character(for keyCode: Int, modifiers: UInt32 = 0) -> String? {
        withCurrentLayout { character(for: keyCode, modifiers: modifiers, in: $0) }
    }

    @MainActor static func baseCharacters(for keyCodes: Range<Int>) -> [Int: String] {
        withCurrentLayout { layout in
            keyCodes.reduce(into: [:]) { characters, keyCode in
                characters[keyCode] = character(for: keyCode, modifiers: 0, in: layout)
            }
        } ?? [:]
    }

    /// The key a synthesized chord must post, so ⌘V still means paste on Dvorak or AZERTY.
    @MainActor static func keyCode(typing character: Character, fallback: Int) -> Int {
        withCurrentInputSource { layout, sourceID in
            keyCode(
                typing: character, inputSourceID: sourceID,
                baseCharacters: (0..<128).reduce(into: [:]) { characters, keyCode in
                    characters[keyCode] = Self.character(for: keyCode, modifiers: 0, in: layout)
                }, fallback: fallback)
        } ?? fallback
    }

    /// A "QWERTY ⌘" layout switches back to QWERTY under ⌘, so its ANSI key is already right.
    static func keyCode(
        typing character: Character, inputSourceID: String?, baseCharacters: [Int: String],
        fallback: Int
    ) -> Int {
        if inputSourceID?.contains("QWERTYCMD") == true { return fallback }
        let wanted = String(character)
        return baseCharacters.filter { $0.value == wanted }.keys.min() ?? fallback
    }

    @MainActor private static func withCurrentLayout<Result>(
        _ body: (UnsafePointer<UCKeyboardLayout>) -> Result?
    ) -> Result? {
        withCurrentInputSource { layout, _ in body(layout) }
    }

    @MainActor private static func withCurrentInputSource<Result>(
        _ body: (UnsafePointer<UCKeyboardLayout>, String?) -> Result?
    ) -> Result? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).map {
            unsafeBitCast($0, to: CFString.self) as String
        }
        // The bytes belong to `source`, which stays retained until `body` returns.
        return withExtendedLifetime(source) {
            body(
                unsafeBitCast(
                    CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self),
                sourceID)
        }
    }

    private static func character(
        for keyCode: Int, modifiers: UInt32, in keyLayout: UnsafePointer<UCKeyboardLayout>
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            modifiers,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// A layout owns its Command table: "Dvorak – QWERTY ⌘" only restores ⌘K to QWERTY through it.
    @MainActor static func character(for event: NSEvent) -> String? {
        character(
            for: Int(event.keyCode),
            modifiers: event.modifierFlags.contains(.command) ? UInt32(cmdKey >> 8) : 0)
    }

    /// SwiftUI exposes the input-source character; recover the logical ASCII key from AppKit.
    @MainActor static func keyEquivalent(fallingBackTo key: KeyEquivalent) -> KeyEquivalent {
        guard let event = NSApp.currentEvent,
            !event.modifierFlags.isDisjoint(with: [.command, .control])
        else { return lowercased(key) }
        return recovered(key, layoutCharacter: character(for: event)?.lowercased().first)
    }

    static func recovered(_ key: KeyEquivalent, layoutCharacter: Character?) -> KeyEquivalent {
        guard !isNamedKey(key), let layoutCharacter,
            layoutCharacter.unicodeScalars.allSatisfy(\.isASCII)
        else { return lowercased(key) }
        return KeyEquivalent(layoutCharacter)
    }

    /// Arrows and page keys: `UCKeyTranslate` answers these with ASCII controls the test admits.
    private static func isNamedKey(_ key: KeyEquivalent) -> Bool {
        key.character.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
    }

    /// Shift uppercases SwiftUI's key, but every chord spells its letter in lower case.
    private static func lowercased(_ key: KeyEquivalent) -> KeyEquivalent {
        key.character.lowercased().first.map { KeyEquivalent($0) } ?? key
    }

    @MainActor static func matches(_ key: KeyEquivalent, character: Character) -> Bool {
        keyEquivalent(fallingBackTo: key) == KeyEquivalent(character)
    }
}
