import Foundation

/// Streams the core's upload and download rates while something on screen shows them.
@MainActor
@Observable
final class ProxyTrafficMonitor {
    enum Viewer: Hashable {
        case window
        case menuBar
    }

    /// Nil while disconnected, or before the first second's numbers arrive.
    private(set) var current: ProxyAPI.Traffic?
    /// Up to the last minute, oldest first.
    private(set) var recent: [ProxyAPI.Traffic] = []
    /// Each second's numbers, and nil when they stop, for a reader outside SwiftUI.
    @ObservationIgnored var onSample: ((ProxyAPI.Traffic?) -> Void)?

    @ObservationIgnored private let manager: ProxyManager
    @ObservationIgnored private var viewers: Set<Viewer> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    static let historyLength = 60

    init(manager: ProxyManager) {
        self.manager = manager
    }

    func setWatching(_ watching: Bool, for viewer: Viewer) {
        if watching { viewers.insert(viewer) } else { viewers.remove(viewer) }
        if viewers.isEmpty {
            task?.cancel()
            task = nil
            current = nil
            recent = []
        } else if task == nil {
            task = Task { [weak self] in await self?.run() }
        }
    }

    /// The stream ends whenever the core stops or restarts, so it is opened again on the next one.
    private func run() async {
        while !Task.isCancelled {
            if let api = manager.controller {
                do {
                    for try await sample in api.traffic() {
                        current = sample
                        recent = Array((recent + [sample]).suffix(Self.historyLength))
                        onSample?(sample)
                    }
                } catch {}
            }
            current = nil
            onSample?(nil)
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
