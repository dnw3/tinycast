import Foundation

enum TranslationSource: Equatable, Sendable {
    case selection
    case capture(documentID: UUID, revision: Int)
}
