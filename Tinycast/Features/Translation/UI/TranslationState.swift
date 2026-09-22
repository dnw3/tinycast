import Foundation
import Observation

@MainActor
@Observable
final class TranslationState {
    enum Phase: Equatable {
        case idle
        case detecting
        case translating
        case finished
        case failed(String)
    }

    var input = ""
    var isComposing = false
    var sourceOverride = ""
    var targetOverride = ""
    var detectedLanguage: String?
    var engine: TranslationPreferences.Engine = .apple
    var output = ""
    var isCopied = false
    var phase: Phase = .idle
    var needsLanguages = false
    var notice: String?
    var deliveryTitle: String?
    var isDelivering = false
    var isPinned = false
    var isExpanded = false
    private(set) var revision = 0

    var source: String? { sourceOverride.isEmpty ? detectedLanguage : sourceOverride }
    var isRunning: Bool { phase == .detecting || phase == .translating }
    var canCopy: Bool { phase == .finished && !output.isEmpty }
    var canSubmit: Bool { !isComposing && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var dismissesOnBlur: Bool { !isPinned && !isDelivering }

    func append(_ delta: String, revision: Int) {
        guard revision == self.revision, phase == .translating else { return }
        output += delta
    }

    func finish(_ output: String, revision: Int) {
        guard revision == self.revision else { return }
        self.output = output
        phase = .finished
    }

    @discardableResult
    func invalidate() -> Int {
        revision += 1
        output = ""
        isCopied = false
        phase = .idle
        needsLanguages = false
        return revision
    }

    func reset(preferences: TranslationPreferences) {
        invalidate()
        input = ""
        isComposing = false
        sourceOverride = ""
        targetOverride = ""
        detectedLanguage = nil
        engine = preferences.engine
        notice = nil
        deliveryTitle = nil
        isDelivering = false
        isPinned = false
        isExpanded = false
    }
}
