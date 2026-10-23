import Foundation

/// Reads the core's open connections once a second while the activity page is on screen.
@MainActor
@Observable
final class ProxyConnectionsMonitor {
    /// Newest first.
    private(set) var connections: [ProxyAPI.Connection] = []
    /// False until the first read after starting, so an empty list is not shown as no traffic.
    private(set) var hasLoaded = false

    @ObservationIgnored private let manager: ProxyManager
    @ObservationIgnored private var task: Task<Void, Never>?

    init(manager: ProxyManager) {
        self.manager = manager
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        connections = []
        hasLoaded = false
    }

    func close(_ id: String) async {
        guard let api = manager.controller else { return }
        try? await api.closeConnection(id)
        connections.removeAll { $0.id == id }
    }

    private func run() async {
        while !Task.isCancelled {
            if let api = manager.controller, let latest = try? await api.connections() {
                guard !Task.isCancelled else { return }
                connections = latest.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
            } else {
                connections = []
            }
            hasLoaded = true
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
