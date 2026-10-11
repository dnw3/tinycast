import Foundation

enum RaycastImportError: Error {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt
    case tooLarge

}
