import Foundation

extension BackupFormatError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadable:
            return String(localized: "This file isn't a Tinycast backup, or it's damaged.")
        case .unsupportedFormat(let found):
            return
                String(localized: "This backup was made by a different version of Tinycast (format \(found), expected \(BackupManifest.currentFormat)). Export again from the Mac that has your setup.")
        }
    }
}
