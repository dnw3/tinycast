import Foundation
import Observation

@MainActor
@Observable
final class CaptureSettingsStore {
    private let defaults: UserDefaults
    private var regions: [CaptureSavedRegion]
    private(set) var uploadDestination: CaptureUploadDestination?
    private(set) var presentationPresets: [CapturePresentationPreset] {
        didSet {
            if let data = try? JSONEncoder().encode(presentationPresets) {
                defaults.set(data, forKey: AppSettingsKey.capturePresentationPresets.rawValue)
            }
        }
    }
    var toolbarItems: Set<CaptureToolbarItem> { toolbarConfiguration.items }
    private(set) var toolbarConfiguration: CaptureToolbarConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(toolbarConfiguration) {
                defaults.set(data, forKey: AppSettingsKey.captureToolbarItems.rawValue)
            }
        }
    }
    var showsCompletionThumbnail: Bool {
        didSet { defaults.set(showsCompletionThumbnail, forKey: AppSettingsKey.captureCompletionThumbnail.rawValue) }
    }
    var preferences: CapturePreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: AppSettingsKey.capturePreferences.rawValue)
            }
        }
    }
    var keepsOriginals: Bool {
        didSet { defaults.set(keepsOriginals, forKey: AppSettingsKey.captureKeepsOriginals.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presentationPresets = defaults.data(forKey: AppSettingsKey.capturePresentationPresets.rawValue)
            .flatMap { $0.count <= 32_768 ? try? JSONDecoder().decode([CapturePresentationPreset].self, from: $0) : nil }
            .flatMap { CapturePresentationPreset.valid($0) ? $0 : nil } ?? []
        toolbarConfiguration = CaptureToolbarConfiguration(
            data: defaults.data(forKey: AppSettingsKey.captureToolbarItems.rawValue))
        showsCompletionThumbnail = defaults.bool(forKey: AppSettingsKey.captureCompletionThumbnail.rawValue)
        uploadDestination = defaults.data(forKey: AppSettingsKey.captureUploadDestination.rawValue)
            .flatMap { $0.count <= 16_384 ? try? JSONDecoder().decode(CaptureUploadDestination.self, from: $0) : nil }
            .flatMap { try? $0.validated() }
        regions = defaults.data(forKey: AppSettingsKey.captureLastRegions.rawValue)
            .flatMap { $0.count <= 16_384 ? try? JSONDecoder().decode([CaptureSavedRegion].self, from: $0) : nil }?
            .filter(\.isValid).suffix(16).map { $0 } ?? []
        preferences =
            defaults.data(forKey: AppSettingsKey.capturePreferences.rawValue)
            .flatMap { try? JSONDecoder().decode(CapturePreferences.self, from: $0) } ?? CapturePreferences()
        keepsOriginals = defaults.bool(forKey: AppSettingsKey.captureKeepsOriginals.rawValue)
    }

    func setToolbarItem(_ item: CaptureToolbarItem, visible: Bool) {
        guard item != .annotation(.select) else { return }
        if visible { toolbarConfiguration.items.insert(item) } else { toolbarConfiguration.items.remove(item) }
    }

    func reorderToolbar(actions: Bool, from offsets: IndexSet, to destination: Int) {
        toolbarConfiguration.reorder(actions: actions, from: offsets, to: destination)
    }

    func moveToolbarItem(_ item: CaptureToolbarItem, by offset: Int) { toolbarConfiguration.move(item, by: offset) }

    func resetToolbar() { toolbarConfiguration = CaptureToolbarConfiguration(items: CaptureToolbarItem.standard) }

    func replacePresentationPresets(_ presets: [CapturePresentationPreset]) -> Bool {
        guard CapturePresentationPreset.valid(presets) else { return false }
        if presentationPresets != presets { presentationPresets = presets }
        return true
    }

    func savePresentationPreset(name: String, presentation: CapturePresentation, replacing id: UUID? = nil) throws {
        guard presentation.isValid else { throw CapturePresentationPreset.Failure.style }
        let preset = CapturePresentationPreset(id: id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), presentation: presentation)
        guard preset.isValid else { throw CapturePresentationPreset.Failure.name }
        var next = presentationPresets
        if let id {
            guard let index = next.firstIndex(where: { $0.id == id }) else {
                throw CapturePresentationPreset.Failure.missing
            }
            next[index] = preset
        } else {
            guard next.count < 20 else { throw CapturePresentationPreset.Failure.limit }
            next.append(preset)
        }
        guard replacePresentationPresets(next) else { throw CapturePresentationPreset.Failure.duplicate }
    }

    func removePresentationPreset(_ id: UUID) {
        presentationPresets.removeAll { $0.id == id }
    }

    func saveUpload(_ destination: CaptureUploadDestination, credential: CaptureUploadCredential) throws {
        let destination = try destination.validated()
        let data = try JSONEncoder().encode(destination)
        guard let secret = String(bytes: try JSONEncoder().encode(credential), encoding: .utf8) else {
            throw CaptureUploadError.credential
        }
        guard !credential.secret.isEmpty else { throw CaptureUploadError.credential }
        try KeychainSecretStore.captureUploads.setSecret(secret, for: destination.id)
        defaults.set(data, forKey: AppSettingsKey.captureUploadDestination.rawValue)
        uploadDestination = destination
    }

    func uploadCredential(for destination: CaptureUploadDestination) throws -> CaptureUploadCredential {
        guard let secret = try KeychainSecretStore.captureUploads.secret(for: destination.id),
            let credential = try? JSONDecoder().decode(CaptureUploadCredential.self, from: Data(secret.utf8))
        else { throw CaptureUploadError.credential }
        return credential
    }

    func removeUpload() throws {
        if let uploadDestination { try KeychainSecretStore.captureUploads.removeSecret(for: uploadDestination.id) }
        defaults.removeObject(forKey: AppSettingsKey.captureUploadDestination.rawValue)
        uploadDestination = nil
    }

    func remember(_ region: CaptureSavedRegion) {
        guard region.isValid else { return }
        regions.removeAll { $0.displayID == region.displayID }
        regions.append(region)
        regions = Array(regions.suffix(16))
        if let data = try? JSONEncoder().encode(regions) {
            defaults.set(data, forKey: AppSettingsKey.captureLastRegions.rawValue)
        }
    }

    func lastRegion(displayID: UInt32, screenSize: CGSize) -> CGRect? {
        regions.last { $0.displayID == displayID && $0.screenSize == screenSize }?.rect
    }
}
