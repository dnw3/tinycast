import Foundation
import Observation

@MainActor
@Observable
final class CaptureSettingsStore {
    private let defaults: UserDefaults
    private var regions: [CaptureSavedRegion]
    private(set) var uploadDestination: CaptureUploadDestination?
    private(set) var toolbarItems: Set<CaptureToolbarItem> {
        didSet {
            if let data = try? JSONEncoder().encode(toolbarItems) {
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
        toolbarItems = defaults.data(forKey: AppSettingsKey.captureToolbarItems.rawValue)
            .flatMap { $0.count <= 8192 ? try? JSONDecoder().decode(Set<CaptureToolbarItem>.self, from: $0) : nil }
            .map { $0.union([.annotation(.select)]) } ?? CaptureToolbarItem.standard
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
        if visible { toolbarItems.insert(item) } else { toolbarItems.remove(item) }
    }

    func resetToolbar() { toolbarItems = CaptureToolbarItem.standard }

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
