import Foundation
import Observation

@MainActor
@Observable
final class TranslationSettingsStore {
    private let defaults: UserDefaults
    @ObservationIgnored private var isReloading = false

    var preferences: TranslationPreferences {
        didSet {
            if !isReloading { save(preferences, key: .translationPreferences) }
        }
    }
    var model: AIModelSelection? {
        didSet {
            if !isReloading { save(model, key: .translationModel) }
        }
    }

    func reload() {
        isReloading = true
        defer { isReloading = false }
        let stored = TranslationSettingsStore(defaults: defaults)
        if preferences != stored.preferences { preferences = stored.preferences }
        if model != stored.model { model = stored.model }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: AppSettingsKey.translationPreferences.rawValue)
            .flatMap { try? JSONDecoder().decode(TranslationPreferences.self, from: $0) }
            ?? TranslationPreferences()
        model = defaults.data(forKey: AppSettingsKey.translationModel.rawValue)
            .flatMap { try? JSONDecoder().decode(AIModelSelection.self, from: $0) }
    }

    private func save(_ value: (some Encodable)?, key: AppSettingsKey) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }
}
