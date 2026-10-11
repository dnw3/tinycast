import Foundation

extension QuicklinkArchive.ArchiveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadable: return String(localized: "This file isn't a Tinycast quicklinks export.")
        case .empty: return String(localized: "This file contains no quicklinks.")
        }
    }
}
