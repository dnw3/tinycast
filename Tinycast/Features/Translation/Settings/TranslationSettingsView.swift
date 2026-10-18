import Combine
import SwiftUI

struct TranslationSettingsView: View {
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        @Bindable var store = coordinator.store
        return Form {
            Section {
                Toggle(isOn: $settings.translationEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .translationTranslation, title: "Enable Translation",
                        subtitle: String(localized: "Translate selected text, or open an empty window and type."))
                }
                TranslationAccessibilityRow()
                    .settingsEnabled(settings.translationEnabled)
            }
            .settingsAnchor(.translationTranslation)
            Group {
                Section {
                    Picker(selection: $store.preferences.firstLanguage) {
                        languageOptions(excluding: store.preferences.secondLanguage)
                    } label: {
                        SettingsRowTitle(.translationLanguages, "Primary language")
                    }
                    Picker(selection: $store.preferences.secondLanguage) {
                        languageOptions(excluding: store.preferences.firstLanguage)
                    } label: {
                        SettingsRowTitle(.translationLanguages, "Secondary language")
                    }
                } header: {
                    SettingsSectionHeader(.translationLanguages)
                } footer: {
                    Text("Primary → secondary. Every other language → primary.")
                }
                Section {
                    Picker(selection: $store.preferences.engine) {
                        ForEach(TranslationPreferences.Engine.allCases, id: \.self) { engine in
                            Text(LocalizedStringKey(engine.title)).tag(engine)
                        }
                    } label: {
                        SettingsRowTitle(.translationEngine, "Default engine")
                    }
                    AIModelSelectionRows(
                        selection: store.model, inheritedTitle: String(localized: "Choose a model…"),
                        select: { store.model = $0 },
                        modelLabel: { SettingsRowTitle(.translationEngine, "Translation model") },
                        effortLabel: { SettingsRowTitle(.translationEngine, "Reasoning effort") })
                } header: {
                    SettingsSectionHeader(.translationEngine)
                } footer: {
                    Text("AI may send text to its provider online. Set up providers in Settings › AI.")
                }
                FeatureCommandsSection(owner: .translation, anchor: .translationCommands)
            }
            .settingsEnabled(settings.translationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.translation)
        .onAppear { coordinator.settingsAppeared(true) }
        .onDisappear { coordinator.settingsAppeared(false) }
    }

    private func languageOptions(excluding identifier: String) -> some View {
        let family = TranslationLanguagePolicy.family(identifier)
        return ForEach(
            coordinator.languages.filter { TranslationLanguagePolicy.family($0) != family }, id: \.self
        ) { language in
            Text(TranslationLanguageService.name(language)).tag(language)
        }
    }
}

/// The Permissions pane's row, so the same grant reads the same way here.
private struct TranslationAccessibilityRow: View {
    @State private var trusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(trusted ? String(localized: "Granted") : String(localized: "Not granted"))
                }
                .foregroundStyle(trusted ? Color.green : Color.orange)
                Button(trusted ? String(localized: "Open…") : String(localized: "Grant Access…")) {
                    if trusted { Permissions.openAccessibilitySettings() } else { _ = Permissions.ensureAccessibility() }
                }
                .help(String(localized: "Opens Privacy & Security › Accessibility."))
            }
        } label: {
            SettingsRowTitle(.translationTranslation, "Accessibility")
            Text("Reads and replaces selected text in other apps.")
        }
        .onReceive(refreshTimer) { _ in
            let now = Permissions.isAccessibilityTrusted()
            if now != trusted { trusted = now }
        }
    }
}
