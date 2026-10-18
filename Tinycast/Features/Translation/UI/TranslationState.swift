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

    struct Notice: Equatable {
        enum Action { case grantAccessibility }
        let text: String
        var action: Action?
    }

    var input = ""
    var isComposing = false
    var sourceOverride = ""
    var targetOverride = ""
    var detectedLanguage: String?
    var engine: TranslationPreferences.Engine = .apple
    var output = ""
    /// The last translation, dimmed while a newer one runs so the Mini window keeps its height.
    var staleOutput = ""
    var isCopied = false
    var phase: Phase = .idle
    var needsLanguages = false
    var notice: Notice?
    var resultNotice: String?
    var deliveryTitle: String?
    var isDelivering = false
    var isPinned = false
    var isExpanded = false
    var origin: TranslationSource = .selection
    var selectedInput = ""
    private(set) var revision = 0

    var source: String? { sourceOverride.isEmpty ? detectedLanguage : sourceOverride }
    var isRunning: Bool { phase == .detecting || phase == .translating }
    var canCopy: Bool { phase == .finished && !output.isEmpty }
    var requestInput: String { origin != .selection && !selectedInput.isEmpty ? selectedInput : input }
    var exceedsLimit: Bool { requestInput.utf8.count > TranslationRequest.maximumInputBytes }
    var canSubmit: Bool { !isComposing && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var dismissesOnBlur: Bool { !isPinned && !isDelivering }

    func append(_ delta: String, revision: Int) {
        guard revision == self.revision, phase == .translating else { return }
        output += delta
    }

    func finish(_ output: String, revision: Int) {
        guard revision == self.revision else { return }
        self.output = output
        staleOutput = ""
        phase = .finished
    }

    func fail(_ message: String) {
        output = ""
        staleOutput = ""
        phase = .failed(message)
    }

    @discardableResult
    func invalidate() -> Int {
        revision += 1
        if !output.isEmpty { staleOutput = output }
        output = ""
        resultNotice = nil
        isCopied = false
        phase = .idle
        needsLanguages = false
        return revision
    }

    func reset(preferences: TranslationPreferences) {
        invalidate()
        staleOutput = ""
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
        origin = .selection
        selectedInput = ""
    }
}
