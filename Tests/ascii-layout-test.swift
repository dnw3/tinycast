import AppKit
import SwiftUI

/// `UCKeyTranslate` answers a named key's keycode with a control character the ASCII test admits.
@main
@MainActor
struct ASCIILayoutTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool) {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    /// What `UCKeyTranslate` hands back for each keycode under ⌘, against SwiftUI's own spelling.
    static let namedKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↑", .upArrow, "\u{1e}"),
        ("↓", .downArrow, "\u{1f}"),
        ("←", .leftArrow, "\u{1c}"),
        ("→", .rightArrow, "\u{1d}"),
        ("⌦", .deleteForward, "\u{7f}"),
        ("⇞", .pageUp, "\u{b}"),
        ("⇟", .pageDown, "\u{c}"),
        ("↖", .home, "\u{1}"),
        ("↘", .end, "\u{4}")
    ]

    /// These four agree with SwiftUI already, and must keep resolving once the arrows are excluded.
    static let controlKeys: [(name: String, key: KeyEquivalent, translated: Character)] = [
        ("↩", .return, "\u{d}"),
        ("⌫", .delete, "\u{8}"),
        ("⇥", .tab, "\u{9}"),
        ("esc", .escape, "\u{1b}"),
        ("space", .space, " ")
    ]

    static func main() {
        print("# a named key is never recovered from the layout")
        for entry in namedKeys {
            check(
                "\(entry.name) keeps SwiftUI's key",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# a key whose control character is already SwiftUI's still resolves")
        for entry in controlKeys {
            check(
                "\(entry.name) resolves to itself",
                ASCIIKeyboardLayout.recovered(entry.key, layoutCharacter: entry.translated)
                    == entry.key)
        }

        print("\n# the recovery still does its job")
        check(
            "a non-QWERTY layout recovers the logical key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("t"), layoutCharacter: "k")
                == KeyEquivalent("k"))
        check(
            "a non-ASCII layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: "ц")
                == KeyEquivalent("k"))
        check(
            "no layout character falls back to SwiftUI's key",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("k"), layoutCharacter: nil)
                == KeyEquivalent("k"))
        check(
            "a shifted letter is still spelled lower case",
            ASCIIKeyboardLayout.recovered(KeyEquivalent("C"), layoutCharacter: nil)
                == KeyEquivalent("c"))

        print("\n# a synthesized ⌘V names the key that types v")
        let qwerty = [9: "v", 8: "c", 47: "."]
        let dvorak = [9: ".", 8: "j", 47: "v"]
        check(
            "QWERTY posts the ANSI key",
            ASCIIKeyboardLayout.keyCode(
                typing: "v", inputSourceID: "com.apple.keylayout.US", baseCharacters: qwerty,
                fallback: 9) == 9)
        check(
            "Dvorak posts the key that types v",
            ASCIIKeyboardLayout.keyCode(
                typing: "v", inputSourceID: "com.apple.keylayout.Dvorak", baseCharacters: dvorak,
                fallback: 9) == 47)
        check(
            "a QWERTY ⌘ layout keeps the ANSI key",
            ASCIIKeyboardLayout.keyCode(
                typing: "v", inputSourceID: "com.apple.keylayout.DVORAK-QWERTYCMD",
                baseCharacters: dvorak, fallback: 9) == 9)
        check(
            "a layout with no v falls back to the ANSI key",
            ASCIIKeyboardLayout.keyCode(
                typing: "v", inputSourceID: nil, baseCharacters: [9: "м"], fallback: 9) == 9)
        check(
            "the live layout answers some key",
            (0..<128).contains(ASCIIKeyboardLayout.keyCode(typing: "v", fallback: 9)))

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
