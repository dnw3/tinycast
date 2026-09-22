import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class TranslationCoordinator {
    let state: TranslationState
    let store: TranslationSettingsStore
    private unowned let core: AppCore
    private let panels = TranslationPanelController()
    private let inputSession = TranslationInputSession()
    private(set) var languages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"]
    private(set) var isVisible = false
    private var settingsVisible = false
    @ObservationIgnored private var target: TranslationTarget?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var languageLoad: Task<Void, Never>?

    var requiresAI: Bool { settingsVisible || (isVisible && state.engine == .ai) }
    var targetLanguage: String {
        TranslationLanguagePolicy.target(
            source: state.source ?? "", first: store.preferences.firstLanguage,
            second: store.preferences.secondLanguage, override: state.targetOverride)
    }
    var canDeliver: Bool { state.canCopy && target != nil && !state.isDelivering }

    init(state: TranslationState, store: TranslationSettingsStore, core: AppCore) {
        self.state = state
        self.store = store
        self.core = core
    }

    func applyEnabled() {
        core.appIndex.setCommandsVisible([.translate], core.settings.translationEnabled)
        if !core.settings.translationEnabled { cancel() }
    }

    func open() {
        guard core.settings.translationEnabled else { return }
        if panels.isKey { panels.focus(); return }
        let app = core.paletteCoordinator.targetApp
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        cancel()
        state.reset(preferences: store.preferences)
        isVisible = true
        loadLanguages()
        capture(from: app)
        panels.present(self, metrics: core.settings.interfaceSize.metrics)
        if state.canSubmit { submit() }
    }

    private func capture(from app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            state.notice = "Type or paste text to translate."
            return
        }
        guard Permissions.isAccessibilityTrusted(), !IsSecureEventInputEnabled() else {
            state.notice = "Type or paste text. Selection and replacement need Accessibility permission."
            return
        }
        target = TranslationTarget.capture(in: app)
        state.deliveryTitle = target?.title
        let selection = AccessibilityText.selection(in: app) ?? target?.selectedText
        if let selection {
            state.input = selection
        }
        if target == nil {
            state.notice = selection == nil
                ? "Type or paste text. No selection could be confirmed in this app."
                : "This source cannot be safely replaced. You can copy the translation."
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        inputSession.cancel()
        state.invalidate()
        state.input = ""
        state.isComposing = false
        state.isDelivering = false
        target = nil
        isVisible = false
        panels.dismiss()
        core.applyInstalledAILifecycle()
    }

    func windowLostFocus() {
        if state.dismissesOnBlur { cancel() }
    }

    func togglePinned() { state.isPinned.toggle() }

    func toggleExpanded() { state.isExpanded.toggle() }

    func inputChanged(_ text: String, isComposing: Bool) {
        guard text != state.input || isComposing != state.isComposing else { return }
        state.input = text
        state.isComposing = isComposing
        invalidate()
        state.detectedLanguage = nil
        let revision = state.revision
        inputSession.schedule(text: text, isComposing: isComposing) { [weak self] in
            guard let self, self.isCurrent(revision) else { return }
            self.submit()
        }
    }

    func changeSource(_ language: String) {
        state.sourceOverride = language
        submit()
    }

    func changeTarget(_ language: String) {
        state.targetOverride = language
        submit()
    }

    func changeEngine(_ engine: TranslationPreferences.Engine) {
        state.engine = engine
        core.applyInstalledAILifecycle()
        submit()
    }

    func submit() {
        invalidate()
        guard state.canSubmit else { return }
        guard state.input.utf8.count <= TranslationRequest.maximumInputBytes else {
            state.phase = .failed("Translate up to 12 KB at a time. Shorten the source text and retry.")
            return
        }
        let revision = state.revision
        let input = state.input
        let preferred = preferredLanguages
        state.phase = .detecting
        task = Task { [weak self] in
            guard let self else { return }
            let detected = await Task.detached {
                TranslationLanguageService.detect(input, preferred: preferred)
            }.value
            guard self.isCurrent(revision) else { return }
            self.state.detectedLanguage = detected
            guard TranslationLanguagePolicy.hasLetters(input) else {
                self.state.finish(input, revision: revision)
                self.state.notice = "No language to translate; numbers and symbols are unchanged."
                return
            }
            guard let source = self.state.source else {
                self.state.phase = .failed("Could not identify the language. Choose a source language.")
                return
            }
            let request = TranslationRequest(text: input, source: source, target: self.targetLanguage)
            await self.translate(request, revision: revision)
        }
    }

    private func translate(_ request: TranslationRequest, revision: Int) async {
        state.phase = .translating
        do {
            let output: String
            switch state.engine {
            case .apple:
                output = try await AppleTranslationService.translate(request)
            case .ai:
                await core.applyInstalledAILifecycle().value
                try Task.checkCancellation()
                let provider = try core.translationProvider()
                output = try await AITranslationService.translate(request, provider: provider) { [weak self] delta in
                    guard let self, self.isCurrent(revision) else { return }
                    self.state.append(delta, revision: revision)
                }
            }
            guard isCurrent(revision) else { return }
            state.finish(output, revision: revision)
        } catch {
            guard isCurrent(revision) else { return }
            state.output = ""
            state.needsLanguages = (error as? AppleTranslationService.Failure) == .needsLanguages
            state.phase = .failed(error.localizedDescription)
        }
    }

    private func invalidate() {
        task?.cancel()
        inputSession.cancel()
        state.invalidate()
        state.isDelivering = false
    }

    private func isCurrent(_ revision: Int) -> Bool {
        !Task.isCancelled && isVisible && state.revision == revision
    }

    private var preferredLanguages: [String] {
        [store.preferences.firstLanguage, store.preferences.secondLanguage]
    }

    func copy() {
        guard state.canCopy else { return }
        Paster.copyPlainText(state.output)
        state.isCopied = true
    }

    func deliver() {
        guard canDeliver, let target else { return }
        state.isDelivering = true
        let revision = state.revision
        core.textInjector.replaceSelection(
            with: state.output, in: target.app,
            validateTarget: { [weak self] in
                guard let self else { return false }
                return self.isVisible && self.state.revision == revision && target.isCurrent()
            },
            onDelivered: { [weak self] in
                guard let self, self.state.revision == revision else { return }
                self.cancel()
                self.core.showMessage("Translation applied")
            },
            onFailed: { [weak self] in
                guard let self, self.state.revision == revision else { return }
                self.state.isDelivering = false
                self.state.notice = "The original field changed or could not accept text. Copy the translation instead."
                self.target = nil
                self.state.deliveryTitle = nil
                self.panels.focus()
            })
    }

    func showSettings() { core.settingsCoordinator.showSettings(tab: .translation) }

    func openLanguageSettings() {
        AppLauncher.openSettingsPane(bundleID: "com.apple.Localization-Settings.extension")
    }

    func settingsAppeared(_ visible: Bool) {
        settingsVisible = visible
        if visible { loadLanguages() }
        core.applyInstalledAILifecycle()
    }

    private func loadLanguages() {
        guard languageLoad == nil else { return }
        languageLoad = Task { [weak self] in
            let languages = await TranslationLanguageService.languages()
            self?.languages = languages
        }
    }
}
