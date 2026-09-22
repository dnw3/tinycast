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
                    SettingsRowTitle(.translationTranslation, "Enable Translation")
                    Text("Translate selected text, or open an empty window and type.")
                }
                Button("Open Translation") { coordinator.open() }
                    .disabled(!settings.translationEnabled)
                Button("Selection & Replacement Permission…") { Permissions.ensureAccessibility() }
            } header: {
                SettingsSectionHeader(.translationTranslation)
            } footer: {
                Text("Typing and copying work without Accessibility. Reading and replacing text in other apps need permission.")
            }
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
                    Text("Primary language → secondary language. All other source languages → primary language.")
                }
                Section {
                    Picker(selection: $store.preferences.engine) {
                        ForEach(TranslationPreferences.Engine.allCases, id: \.self) { engine in
                            Text(engine.title).tag(engine)
                        }
                    } label: {
                        SettingsRowTitle(.translationEngine, "Default engine")
                    }
                    AIModelSelectionRows(
                        selection: store.model, inheritedTitle: "Choose a model…",
                        select: { store.model = $0 },
                        modelLabel: { SettingsRowTitle(.translationEngine, "Translation model") },
                        effortLabel: { SettingsRowTitle(.translationEngine, "Reasoning effort") })
                } header: {
                    SettingsSectionHeader(.translationEngine)
                } footer: {
                    Text(
                        "Apple runs on this Mac with downloaded languages. AI uses the selected provider "
                        + "and may send text online. Configure providers in Settings → AI.")
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
        return ForEach(coordinator.languages.filter { TranslationLanguagePolicy.family($0) != family }, id: \.self) { language in
            Text(TranslationLanguageService.name(language)).tag(language)
        }
    }
}
