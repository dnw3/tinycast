import Foundation
import Observation

@MainActor
@Observable
final class CaptureTranslationReviewState {
    var translation: CaptureTranslation
    var source: String
    var engine: TranslationPreferences.Engine
    var index = 0
    var revision: Int
    var needsLanguages = false

    init(translation: CaptureTranslation, source: String, engine: TranslationPreferences.Engine, revision: Int) {
        self.translation = translation
        self.source = source
        self.engine = engine
        self.revision = revision
    }
}
