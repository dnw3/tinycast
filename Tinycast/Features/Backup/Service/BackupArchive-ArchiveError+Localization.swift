import Foundation

extension BackupArchive.ArchiveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cannotWrite: return String(localized: "Couldn't write the backup file.")
        case .cannotRead: return String(localized: "This file isn't a Tinycast backup, or it's damaged.")
        }
    }
}
