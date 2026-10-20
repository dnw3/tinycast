import Foundation

/// A command line split the way a POSIX shell splits it, so a wrapped script reads as written.
enum ShellWords {
    private static let shells: Set<String> = ["bash", "zsh", "sh"]
    private static let scriptFlags: Set<String> = ["-c", "-lc", "-cl"]

    /// The script inside `bash -lc '…'` and its kin, as Codex runs every command; else the line.
    static func script(of command: String) -> String {
        guard let words = split(command), words.count == 3,
            shells.contains((words[0] as NSString).lastPathComponent), scriptFlags.contains(words[1])
        else { return command }
        return words[2]
    }

    /// Quotes and backslashes resolved, adjacent quoted runs joined; nil when a quote never closes.
    static func split(_ line: String) -> [String]? {
        let characters = Array(line)
        var words: [String] = []
        var word = ""
        var inWord = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case " ", "\t", "\n":
                if inWord { words.append(word) }
                word = ""
                inWord = false
            case "'":
                inWord = true
                guard let close = characters[(index + 1)...].firstIndex(of: "'") else { return nil }
                word += String(characters[(index + 1)..<close])
                index = close
            case "\"":
                inWord = true
                guard let close = doubleQuoted(characters, from: index + 1, into: &word) else {
                    return nil
                }
                index = close
            case "\\":
                inWord = true
                if index + 1 < characters.count {
                    index += 1
                    if characters[index] != "\n" { word.append(characters[index]) }
                }
            default:
                inWord = true
                word.append(character)
            }
            index += 1
        }
        if inWord { words.append(word) }
        return words
    }

    /// Inside double quotes a backslash escapes only these, and a newline it escapes disappears.
    private static func doubleQuoted(
        _ characters: [Character], from start: Int, into word: inout String
    ) -> Int? {
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\"" { return index }
            if character == "\\", index + 1 < characters.count,
                "$`\"\\\n".contains(characters[index + 1])
            {
                if characters[index + 1] != "\n" { word.append(characters[index + 1]) }
                index += 2
                continue
            }
            word.append(character)
            index += 1
        }
        return nil
    }
}
