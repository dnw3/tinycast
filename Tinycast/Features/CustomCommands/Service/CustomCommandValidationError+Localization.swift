import Foundation

extension CustomCommandValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the command.")
        case .emptyCommand: return String(localized: "Enter a command to run.")
        case .duplicateName: return String(localized: "A custom command with this name already exists.")
        case .invalidCharacter: return String(localized: "Names and commands cannot contain null characters.")
        }
    }
}
