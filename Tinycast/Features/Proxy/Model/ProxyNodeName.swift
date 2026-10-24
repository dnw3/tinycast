import Foundation

/// A node name read as its short title and the note a provider tacks on after a colon, bar or dash.
struct ProxyNodeName: Equatable, Sendable {
    var title: String
    var note: String?

    private static let separators = ["：", ":", "｜", "|", " - ", " – ", " — "]
    /// A longer head is a description itself, not a name like `香港01` that a note follows.
    private static let longestTitle = 14

    init(_ name: String) {
        let bare = ProxyRegion.leadingFlag(of: name)?.rest ?? name
        title = bare
        note = nil
        let cuts = Self.separators.compactMap { bare.range(of: $0) }
        guard let cut = cuts.min(by: { $0.lowerBound < $1.lowerBound }) else { return }
        let head = bare[..<cut.lowerBound].trimmingCharacters(in: .whitespaces)
        let tail = bare[cut.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, !tail.isEmpty, head.count <= Self.longestTitle,
            head.contains(where: \.isNumber)
        else { return }
        title = head
        note = tail
    }
}
