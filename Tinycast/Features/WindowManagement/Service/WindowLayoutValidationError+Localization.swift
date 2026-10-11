import Foundation

extension WindowLayoutValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the layout.")
        case .duplicateName: return String(localized: "A window layout with this name already exists.")
        case .noEntries: return String(localized: "Add at least one app to the layout.")
        case .invalidCharacter: return String(localized: "Names cannot contain null characters.")
        }
    }
}
