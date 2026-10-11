import AppKit
import Carbon.HIToolbox
import Observation
import OSLog

@MainActor
@Observable
final class TranslationCoordinator {
    let state: TranslationState
    let store: TranslationSettingsStore
    private unowned let core: AppCore
    private let panels = TranslationPanelController()
    private let inputSession = TranslationInputSession()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tinycast.app", category: "TranslationSelection")
    private(set) var languages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"]
    private(set) var isVisible = false
    private var settingsVisible = false
    private var imageTranslations = 0
    @ObservationIgnored private var target: TranslationTarget?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var languageLoad: Task<Void, Never>?
    @ObservationIgnored private var retainedSource: AnyObject?
    var sourcePreview: CGImage?

    var requiresAI: Bool { settingsVisible || imageTranslations > 0 || (isVisible && state.engine == .ai) }
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
        let revision = state.revision
        task = Task { [weak self] in
            guard let self else { return }
            await self.capture(from: app, revision: revision)
            guard self.isCurrent(revision) else { return }
            self.task = nil
            self.panels.present(self, metrics: self.core.settings.interfaceSize.metrics)
            if self.state.canSubmit { self.submit() }
        }
    }

    func open(
        text: String, source: TranslationSource, translate: Bool, notice: String?,
        retaining: AnyObject, preview: CGImage? = nil
    ) {
        cancel()
        state.reset(preferences: store.preferences)
        state.origin = source
        state.input = text
        state.notice = notice
        state.isExpanded = true
        retainedSource = retaining
        sourcePreview = preview
        target = nil
        isVisible = true
        loadLanguages()
        panels.present(self, metrics: core.settings.interfaceSize.metrics)
        if translate { submit() }
    }

    func copySource() {
        Paster.copyPlainText(state.selectedInput.isEmpty ? state.input : state.selectedInput)
    }

    func translateImage(
        _ request: TranslationBatchRequest, engine: TranslationPreferences.Engine
    ) async throws -> [String] {
        guard core.settings.translationEnabled else {
            throw AIProviderError.unavailable(
                String(localized: "Enable Translation in Settings to translate this image."))
        }
        if engine == .apple { return try await AppleTranslationService.translate(request) }
        imageTranslations += 1
        defer { imageTranslations -= 1; core.applyInstalledAILifecycle() }
        await core.applyInstalledAILifecycle().value
        try Task.checkCancellation()
        return try await AITranslationService.translate(request, provider: core.translationProvider())
    }

    private func capture(from app: NSRunningApplication?, revision: Int) async {
        guard isCurrent(revision) else { return }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            state.notice = String(localized: "Type or paste text to translate.")
            return
        }
        guard Permissions.isAccessibilityTrusted() else {
            logger.info("Selection unavailable: Accessibility not granted")
            state.notice = String(
                localized: "Type or paste text. Selection and replacement need Accessibility permission.")
            return
        }
        guard !IsSecureEventInputEnabled() else {
            state.notice = String(localized: "Secure input is active. Type or paste text to translate.")
            return
        }
        target = TranslationTarget.capture(in: app)
        state.deliveryTitle = target?.title
        var selection = AccessibilityText.selection(in: app) ?? target?.selectedText
        var usedMenu = false
        if selection == nil, target == nil, let copy = TranslationSelectionReader.copyAction(in: app) {
            usedMenu = true
            selection = await core.textInjector.copySelection(from: app, performCopy: copy)
        }
        guard isCurrent(revision) else { return }
        if usedMenu, NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            cancel()
            return
        }
        let bundleID = app.bundleIdentifier ?? "unknown"
        logger.info("Selection app=\(bundleID, privacy: .public) menu=\(usedMenu) found=\(selection != nil)")
        if let selection {
            state.input = selection
        }
        if target == nil {
            state.notice =
                selection == nil
                ? String(localized: "Type or paste text. No selection could be confirmed in this app.")
                : String(localized: "This source cannot be safely replaced. You can copy the translation.")
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
        retainedSource = nil
        sourcePreview = nil
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
        state.selectedInput = ""
        state.isComposing = isComposing
        invalidate()
        state.detectedLanguage = nil
        if state.origin != .selection { return }
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
        guard core.settings.translationEnabled else {
            state.notice = String(
                localized:
                    "Enable Translation in Settings to translate this text. You can still copy and edit it.")
            return
        }
        let input =
            state.origin != .selection && !state.selectedInput.isEmpty ? state.selectedInput : state.input
        guard input.utf8.count <= TranslationRequest.maximumInputBytes else {
            state.phase = .failed(
                String(localized: "Translate up to 12 KB at a time. Shorten the source text and retry."))
            return
        }
        let revision = state.revision
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
                self.state.notice = String(
                    localized: "No language to translate; numbers and symbols are unchanged.")
                return
            }
            guard let source = self.state.source else {
                self.state.phase = .failed(
                    String(localized: "Could not identify the language. Choose a source language."))
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
                output = try await AITranslationService.translate(request, provider: provider) {
                    [weak self] delta in
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
            state.phase = .failed(
                Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil))
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
            isValid: { [weak self] in
                guard let self else { return false }
                return self.isVisible && self.state.revision == revision && target.isCurrent()
            },
            onDelivered: { [weak self] in
                guard let self, self.state.revision == revision else { return }
                self.cancel()
                self.core.showMessage(String(localized: "Translation applied"))
            },
            onFailed: { [weak self] in
                guard let self, self.state.revision == revision else { return }
                self.state.isDelivering = false
                self.state.notice = String(
                    localized:
                        "The original field changed or could not accept text. Copy the translation instead.")
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
