import SwiftUI

/// A diff in the transcript's own colours, so an edit reads the same on its card and on its row.
enum ChatDiffText {
    /// `naming` turns each file's `---` / `+++` pair into the one line that names the file.
    static func attributed(
        _ diff: String, naming: ((_ before: String, _ after: String) -> String)? = nil
    ) -> AttributedString {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        var text = AttributedString()
        var index = 0
        var isFirst = true
        while index < lines.count {
            let line = lines[index]
            var piece: AttributedString
            if let naming, line.hasPrefix("--- "), index + 1 < lines.count, lines[index + 1].hasPrefix("+++ ") {
                let name = naming(String(line.dropFirst(4)), String(lines[index + 1].dropFirst(4)))
                // A blank line ends the previous file, so the next one's name heads its own block.
                piece = AttributedString(isFirst ? name : "\n" + name)
                piece.foregroundColor = Theme.Colors.textSecondary
                index += 1
            } else {
                piece = AttributedString(String(line))
                if line.hasPrefix("+++ ") || line.hasPrefix("--- ") || line.hasPrefix("@@") {
                    piece.foregroundColor = Theme.Colors.textTertiary
                } else if line.hasPrefix("+") {
                    piece.foregroundColor = Theme.Colors.Syntax.inserted
                } else if line.hasPrefix("-") {
                    piece.foregroundColor = Theme.Colors.Syntax.deleted
                }
            }
            if !isFirst { text += AttributedString("\n") }
            text += piece
            isFirst = false
            index += 1
        }
        return text
    }
}
