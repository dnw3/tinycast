import Foundation

extension CustomQuickActionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Give the action a name.")
        case .emptyInstructions: return String(localized: "Tell the model what the action should do.")
        case .invalidCharacter: return String(localized: "The name contains a character Tinycast can't store.")
        case .storageUnavailable: return String(localized: "Tinycast couldn't save to its actions file.")
        }
    }
}
