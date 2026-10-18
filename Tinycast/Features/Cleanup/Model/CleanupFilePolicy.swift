import Foundation

/// Why a personal file is offered; each kind is its own reviewed row, and all go to the Trash.
enum CleanupFileKind: String, Sendable, CaseIterable {
    case installer
    case incompleteDownload
    case duplicate
    case large
    case old
    case macOSInstaller

    var target: CleanupTargetID {
        switch self {
        case .installer: return .installers
        case .incompleteDownload: return .incompleteDownloads
        case .duplicate: return .duplicates
        case .large: return .largeFiles
        case .old: return .oldFiles
        case .macOSInstaller: return .macOSInstallers
        }
    }
}

/// What the effect layer read about one personal file, at one moment.
struct CleanupFileEvidence: Equatable, Sendable {
    let kind: CleanupFileKind
    /// Bytes only this file holds; an APFS clone shares the rest with its source.
    let bytes: Int64
    /// Later of last open and last change, the closest thing to "last used" a stat gives.
    let lastUsed: Date
    let isRegularFile: Bool
    /// The copy kept for a duplicate; every other copy with the same content is offered.
    let keeper: String?
    /// Content digest shared with `keeper`, read by the effect layer.
    let matchesKeeper: Bool
    /// The bundle identifier of an installer app, read from its Info.plist.
    let bundleID: String?
    let largeThreshold: Int64
    let now: Date
}

/// Which personal files are offered. None is ever safe: they are the user's, so all are reviewed
/// and go to the Trash, where they can be put back.
enum CleanupFilePolicy {
    /// Where the walk looks: the folders people fill by hand, never the media libraries.
    static let roots = ["Downloads", "Desktop", "Documents", "Movies"]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
    static let incompleteExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]
    /// An unfinished download younger than this may still be downloading.
    static let incompleteMinimumAge: TimeInterval = 86_400
    static let oldMinimumBytes: Int64 = 100 << 20
    static let oldAge: TimeInterval = 365 * 86_400
    static let duplicateMinimumBytes: Int64 = 10 << 20
    static let defaultLargeThreshold: Int64 = 1 << 30
    static let largeThresholdChoices: [Int64] = [100 << 20, 500 << 20, 1 << 30, 5 << 30]
    /// Bundles and libraries are one document each; nothing inside one is offered on its own.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle", "logicx",
        "band", "imovielibrary", "xcarchive", "rtfd", "pages", "numbers", "key", "sparsebundle", "pvm", "utm",
        "vmwarevm", "photolibrary", "aplibrary", "lrcat", "lrdata"
    ]

    /// The kind a file under one of the roots is offered as, most specific first; nil when none.
    static func classify(
        name: String, bytes: Int64, lastUsed: Date, isRegularFile: Bool, largeThreshold: Int64, now: Date
    ) -> CleanupFileKind? {
        let ext = (name as NSString).pathExtension.lowercased()
        // Safari's `.download` is a folder; every other kind is a plain file.
        if incompleteExtensions.contains(ext), now.timeIntervalSince(lastUsed) >= incompleteMinimumAge {
            return .incompleteDownload
        }
        guard isRegularFile else { return nil }
        if installerExtensions.contains(ext) { return .installer }
        if bytes >= largeThreshold { return .large }
        if bytes >= oldMinimumBytes, now.timeIntervalSince(lastUsed) >= oldAge { return .old }
        return nil
    }

    /// True when `relative` (home-relative components) is a path the walk may offer.
    static func isWalkable(_ relative: [String]) -> Bool {
        guard relative.count >= 2, let first = relative.first,
            roots.contains(where: { $0.compare(first, options: .caseInsensitive) == .orderedSame })
        else { return false }
        return !relative.dropFirst().contains { $0.hasPrefix(".") || isPackage($0) }
    }

    static func isPackage(_ component: String) -> Bool {
        packageExtensions.contains((component as NSString).pathExtension.lowercased())
    }

    /// The gate's re-decision from evidence; `relative` is nil only for a path outside home.
    static func verify(path: String, relative: [String]?, evidence: CleanupFileEvidence) -> Bool {
        if evidence.kind == .macOSInstaller {
            let name = (path as NSString).lastPathComponent
            return relative == nil && (path as NSString).deletingLastPathComponent == "/Applications"
                && name.hasPrefix("Install macOS ") && name.hasSuffix(".app")
                && evidence.bundleID?.hasPrefix("com.apple.InstallAssistant") == true
        }
        guard let relative, isWalkable(relative), let name = relative.last else { return false }
        if evidence.kind == .duplicate {
            guard evidence.isRegularFile, let keeper = evidence.keeper else { return false }
            return keeper != path && evidence.matchesKeeper
        }
        return classify(
            name: name, bytes: evidence.bytes, lastUsed: evidence.lastUsed, isRegularFile: evidence.isRegularFile,
            largeThreshold: evidence.largeThreshold, now: evidence.now) == evidence.kind
    }

    /// The copy a duplicate set keeps: the earliest created, then the shortest path, so it is stable.
    static func keeper(of copies: [(path: String, created: Date)]) -> String? {
        copies.min { lhs, rhs in
            if lhs.created != rhs.created { return lhs.created < rhs.created }
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }?.path
    }
}
