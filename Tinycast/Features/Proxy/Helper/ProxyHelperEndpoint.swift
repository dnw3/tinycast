import Foundation

/// One client's side of the helper; each call is handed to the supervisor in arrival order.
final class ProxyHelperEndpoint: NSObject, ProxyHelperXPC {
    private let supervisor: ProxyHelperSupervisor

    init(supervisor: ProxyHelperSupervisor) {
        self.supervisor = supervisor
    }

    func handshake(reply: @escaping @Sendable (Int) -> Void) {
        reply(ProxyHelperWire.version)
    }

    func status(reply: @escaping @Sendable (Data) -> Void) {
        Task { @MainActor [supervisor] in reply((try? JSONEncoder().encode(supervisor.status)) ?? Data()) }
    }

    func installCore(
        _ file: FileHandle, sha256: String, signed: Bool, reply: @escaping @Sendable (Data?) -> Void
    ) {
        perform(reply) { supervisor throws(ProxyHelperFailure) in
            try await supervisor.installCore(from: file, sha256: sha256, signed: signed)
        }
    }

    func writeFile(_ name: String, contents: Data, reply: @escaping @Sendable (Data?) -> Void) {
        perform(reply) { supervisor throws(ProxyHelperFailure) in
            try supervisor.writeFile(name, contents: contents)
        }
    }

    func removeFile(_ name: String, reply: @escaping @Sendable (Data?) -> Void) {
        perform(reply) { supervisor throws(ProxyHelperFailure) in try supervisor.removeFile(name) }
    }

    func start(
        _ config: Data, placeholderDNS: Bool, outlivesClient: Bool, reply: @escaping @Sendable (Data?) -> Void
    ) {
        perform(reply) { supervisor throws(ProxyHelperFailure) in
            try await supervisor.start(
                config: config, placeholderDNS: placeholderDNS, outlivesClient: outlivesClient)
        }
    }

    func stop(reply: @escaping @Sendable () -> Void) {
        Task { @MainActor [supervisor] in
            supervisor.enqueue { supervisor in
                await supervisor.stop()
                reply()
            }
        }
    }

    /// Not queued: it waits on nothing, and a client reads from the core while a reload runs.
    func openController(reply: @escaping @Sendable (FileHandle?, Data?) -> Void) {
        Task { @MainActor [supervisor] in
            do throws(ProxyHelperFailure) {
                let descriptor = try supervisor.openController()
                reply(FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), nil)
            } catch {
                reply(nil, error.encoded)
            }
        }
    }

    private func perform(
        _ reply: @escaping @Sendable (Data?) -> Void,
        _ operation: @escaping @MainActor (ProxyHelperSupervisor) async throws(ProxyHelperFailure) -> Void
    ) {
        Task { @MainActor [supervisor] in
            supervisor.enqueue { supervisor in
                do throws(ProxyHelperFailure) {
                    try await operation(supervisor)
                    reply(nil)
                } catch {
                    reply(error.encoded)
                }
            }
        }
    }
}
