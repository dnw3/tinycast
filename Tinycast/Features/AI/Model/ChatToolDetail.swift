import Foundation

/// What a tool step was given and gave back, beyond the one line its row shows.
struct ChatToolDetail: Equatable, Hashable, Sendable {
    /// Past this, the start of a command or diff is what says what it was.
    static let inputLimit = 16_384
    /// Past this, the end of a log is where a failure says why.
    static let outputLimit = 16_384

    /// A command, path or diff where the step's shape is known; otherwise its raw input, as JSON.
    private(set) var input: String
    /// Claude's own sentence for a command, asked for in the reader's language.
    private(set) var explanation: String?
    /// Standard output and error together, as the CLI reported them.
    private(set) var output: String?
    private(set) var exitCode: Int?
    /// Earlier output was dropped at `outputLimit`.
    private(set) var isOutputTrimmed = false

    init(input: String, explanation: String? = nil) {
        self.input = input.count > Self.inputLimit ? String(input.prefix(Self.inputLimit)) + "…" : input
        self.explanation = explanation.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// As history saved it, already within its limits.
    init(
        input: String, explanation: String?, output: String?, exitCode: Int?, isOutputTrimmed: Bool
    ) {
        self.input = input
        self.explanation = explanation
        self.output = output
        self.exitCode = exitCode
        self.isOutputTrimmed = isOutputTrimmed
    }

    mutating func record(output: String?, exitCode: Int?) {
        if let output, !output.isEmpty { (self.output, isOutputTrimmed) = Self.tail(of: output) }
        if let exitCode { self.exitCode = exitCode }
    }

    /// A result as text, sent as a string or as MCP content blocks; an image block has none.
    static func text(of content: JSONValue?) -> String? {
        if let string = content?.stringValue { return string }
        let texts = (content?.arrayValue ?? []).compactMap { block -> String? in
            guard let fields = block.objectValue, fields["type"]?.stringValue == "text" else { return nil }
            return fields["text"]?.stringValue
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// Lines a unified diff adds and removes; the `---` / `+++` lines naming its files are neither.
    static func diffCounts(in diff: String) -> (added: Int, removed: Int) {
        diff.split(separator: "\n").reduce(into: (added: 0, removed: 0)) { counts, line in
            if line.hasPrefix("+"), !line.hasPrefix("+++ ") {
                counts.added += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("--- ") {
                counts.removed += 1
            }
        }
    }

    /// A long block's first or last `limit` lines, and how many lines it leaves out.
    static func excerpt(of text: String, lines limit: Int, fromEnd: Bool) -> (text: String, hidden: Int) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > limit else { return (text, 0) }
        let kept = fromEnd ? lines.suffix(limit) : lines.prefix(limit)
        return (kept.joined(separator: "\n"), lines.count - limit)
    }

    /// Opens on a line boundary where one falls in the kept stretch, never mid-line.
    static func tail(of text: String) -> (text: String, trimmed: Bool) {
        guard text.count > outputLimit else { return (text, false) }
        let kept = text.suffix(outputLimit)
        let start = kept.firstIndex(of: "\n").map { kept.index(after: $0) } ?? kept.startIndex
        return (String(kept[start...]), true)
    }
}
