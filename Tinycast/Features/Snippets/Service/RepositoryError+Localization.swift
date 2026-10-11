import Foundation

extension SnippetRepository.RepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .conflict(let fileURL, _, _):
            return
                String(localized: "The snippet changed on disk. Reload it before saving or deleting. (\(fileURL.lastPathComponent))")
        case .fileNotFound(let fileURL):
            return String(localized: "The snippet file no longer exists. (\(fileURL.lastPathComponent))")
        case .invalidFileLocation(let fileURL):
            return String(localized: "The snippet file is outside this Tinycast channel. (\(fileURL.path))")
        case .io(let fileURL, let message):
            return String(localized: "Could not access \(fileURL.path): \(message)")
        }
    }
}
