import Foundation

extension QuicklinkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the quicklink.")
        case .emptyLink: return String(localized: "Enter a link to open.")
        case .duplicateName: return String(localized: "A quicklink with this name already exists.")
        case .unresolvableLink:
            return String(localized: "This doesn't look like a URL, file path, or deeplink.")
        case .invalidCharacter: return String(localized: "Names and links cannot contain null characters.")
        case .storageUnavailable:
            return String(localized: "The quicklinks database could not be opened, so changes can't be saved.")
        }
    }
}
