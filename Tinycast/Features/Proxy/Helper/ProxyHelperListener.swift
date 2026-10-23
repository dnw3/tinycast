import Foundation

/// Admits only the Tinycast the grant names: its signature on the listener, its user here.
@MainActor
final class ProxyHelperListener: NSObject, NSXPCListenerDelegate {
    let grant: ProxyHelperGrant
    let supervisor: ProxyHelperSupervisor
    private let idleTimeout: Duration
    private let onIdle: @MainActor () -> Void
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var idleTask: Task<Void, Never>?

    /// NSXPCConnection is documented thread-safe; this carries it to the main actor and back.
    private final class Peer: @unchecked Sendable {
        let connection: NSXPCConnection

        init(_ connection: NSXPCConnection) {
            self.connection = connection
        }
    }

    init(
        grant: ProxyHelperGrant, supervisor: ProxyHelperSupervisor, idleTimeout: Duration = .seconds(10),
        onIdle: @escaping @MainActor () -> Void
    ) {
        self.grant = grant
        self.supervisor = supervisor
        self.idleTimeout = idleTimeout
        self.onIdle = onIdle
        super.init()
        supervisor.onChange = { [weak self] in self?.supervisorDidChange() }
    }

    var clientCount: Int { peers.count }

    /// On the listener, so a connection failing the requirement never reaches the delegate.
    func listen(on listener: NSXPCListener, requiring requirement: String) {
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = self
        listener.activate()
        scheduleIdleCheck()
    }

    nonisolated func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard connection.effectiveUserIdentifier == grant.uid else { return false }
        let peer = Peer(connection)
        connection.exportedInterface = ProxyHelperWire.helperInterface()
        connection.exportedObject = ProxyHelperEndpoint(supervisor: supervisor)
        connection.remoteObjectInterface = ProxyHelperWire.clientInterface()
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.remove(peer) }
        }
        Task { @MainActor in self.add(peer) }
        connection.activate()
        return true
    }

    private func add(_ peer: Peer) {
        peers[ObjectIdentifier(peer)] = peer
        clientsDidChange()
    }

    private func remove(_ peer: Peer) {
        guard peers.removeValue(forKey: ObjectIdentifier(peer)) != nil else { return }
        clientsDidChange()
    }

    private func clientsDidChange() {
        supervisor.clientsDidChange(count: peers.count)
        scheduleIdleCheck()
    }

    private func supervisorDidChange() {
        if let status = try? JSONEncoder().encode(supervisor.status) {
            for peer in peers.values {
                let client =
                    peer.connection.remoteObjectProxyWithErrorHandler { _ in } as? ProxyHelperClientXPC
                client?.helperStatusDidChange(status)
            }
        }
        scheduleIdleCheck()
    }

    /// launchd starts the helper again on the next message, so an idle one gives its memory back.
    private func scheduleIdleCheck() {
        idleTask?.cancel()
        idleTask = nil
        guard peers.isEmpty, supervisor.isIdle else { return }
        idleTask = Task { [weak self, idleTimeout] in
            try? await Task.sleep(for: idleTimeout)
            guard !Task.isCancelled, let self, self.peers.isEmpty, self.supervisor.isIdle else { return }
            self.onIdle()
        }
    }
}
