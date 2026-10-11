import Foundation

extension RoomValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the room.")
        case .duplicateName: return String(localized: "A room with this name already exists.")
        case .noWindows: return String(localized: "Choose at least one window for the room.")
        case .invalidCharacter: return String(localized: "Names cannot contain null characters.")
        }
    }
}
