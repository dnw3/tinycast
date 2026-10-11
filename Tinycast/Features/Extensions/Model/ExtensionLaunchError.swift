import Foundation

enum ExtensionLaunchError: Error {
    case unknownCommand(String)
    case unsupported(String)
    case notBuilt(String)
    case missingPreferences([ExtensionPreferenceSchema])

}
