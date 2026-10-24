import Foundation

/// Who may drive the helper, as the approved install recorded it: Tinycast and its user.
struct ProxyHelperGrant: Codable, Equatable, Sendable {
    var appIdentifier: String
    /// SHA-1 of the signing certificate, the form a code requirement's `certificate leaf` takes.
    var leafHash: String
    var uid: UInt32

    var isValid: Bool { Self.isIdentifier(appIdentifier) && Self.isLeafHash(leafHash) }

    var appRequirement: String { requirement(for: appIdentifier) }
    var helperRequirement: String { requirement(for: appIdentifier + ProxyHelperLayout.suffix) }
    /// What the core embedded in Tinycast is signed as; a downloaded core is trusted by its digest.
    var coreRequirement: String { requirement(for: appIdentifier + ".mihomo") }

    private func requirement(for identifier: String) -> String {
        "identifier \"\(identifier)\" and certificate leaf = H\"\(leafHash)\""
    }

    /// Reverse-DNS letters, digits, dots and dashes: safe in a requirement, path and shell.
    static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 200 && !text.hasPrefix(".") && !text.hasSuffix(".")
            && !text.contains("..")
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    static func isLeafHash(_ text: String) -> Bool { isLowercaseHex(text, count: 40) }

    /// A SHA-256 as Tinycast and the helper exchange it.
    static func isDigest(_ text: String) -> Bool { isLowercaseHex(text, count: 64) }

    static func isLowercaseHex(_ text: String, count: Int) -> Bool {
        text.utf8.count == count
            && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
