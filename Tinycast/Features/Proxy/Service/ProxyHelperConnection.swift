import Foundation
import Synchronization

/// Tinycast's line to the TUN helper: a privileged Mach connection requiring its signature.
final class ProxyHelperConnection: Sendable {
    enum Failure: Error, Equatable, Sendable {
        /// No answer: not installed, not running, or the helper is not the one Tinycast installed.
        case unavailable
        case helper(ProxyHelperFailure)
    }

    /// What the helper process must satisfy; anything else answering under its name is refused.
    private let requirement: String
    private let connector: @Sendable () -> NSXPCConnection
    private let onStatus: @Sendable (ProxyHelperStatus) -> Void
    private let onInterruption: @Sendable () -> Void
    private let line = Mutex<Line?>(nil)

    /// NSXPCConnection is documented thread-safe, which the compiler cannot see.
    private final class Line: @unchecked Sendable {
        let connection: NSXPCConnection

        init(_ connection: NSXPCConnection) {
            self.connection = connection
        }
    }

    /// The installed helper, which launchd starts on the first message.
    convenience init(
        layout: ProxyHelperLayout, grant: ProxyHelperGrant,
        onStatus: @escaping @Sendable (ProxyHelperStatus) -> Void,
        onInterruption: @escaping @Sendable () -> Void
    ) {
        let label = layout.label
        self.init(requirement: grant.helperRequirement, onStatus: onStatus, onInterruption: onInterruption) {
            NSXPCConnection(machServiceName: label, options: .privileged)
        }
    }

    /// `onInterruption` runs when the helper process went away; the next call starts it again.
    init(
        requirement: String, onStatus: @escaping @Sendable (ProxyHelperStatus) -> Void,
        onInterruption: @escaping @Sendable () -> Void, connector: @escaping @Sendable () -> NSXPCConnection
    ) {
        self.requirement = requirement
        self.connector = connector
        self.onStatus = onStatus
        self.onInterruption = onInterruption
    }

    /// Lets an idle helper exit; the next call connects again.
    func close() {
        let closed = line.withLock { line in
            defer { line = nil }
            return line
        }
        closed?.connection.invalidate()
    }

    // MARK: - Calls

    func handshake() async throws(Failure) -> Int {
        try await call(timeout: .seconds(10)) { helper, finish in
            helper.handshake { _ = finish(.success($0)) }
        }
    }

    func status() async throws(Failure) -> ProxyHelperStatus {
        try await call(timeout: .seconds(10)) { helper, finish in
            helper.status { data in
                let status = try? JSONDecoder().decode(ProxyHelperStatus.self, from: data)
                _ = finish(status.map(Result.success) ?? .failure(.unavailable))
            }
        }
    }

    func installCore(_ file: FileHandle, sha256: String, signed: Bool) async throws(Failure) {
        try await call(timeout: .seconds(120)) { helper, finish in
            helper.installCore(file, sha256: sha256, signed: signed) { _ = finish(Self.result($0)) }
        }
    }

    func writeFile(_ name: String, contents: Data) async throws(Failure) {
        try await call(timeout: .seconds(30)) { helper, finish in
            helper.writeFile(name, contents: contents) { _ = finish(Self.result($0)) }
        }
    }

    func removeFile(_ name: String) async throws(Failure) {
        try await call(timeout: .seconds(10)) { helper, finish in
            helper.removeFile(name) { _ = finish(Self.result($0)) }
        }
    }

    /// Covers the helper's ten-second wait for a new core, or a reload that fetches nothing.
    func start(_ config: Data, placeholderDNS: Bool, outlivesClient: Bool) async throws(Failure) {
        try await call(timeout: .seconds(150)) { helper, finish in
            helper.start(config, placeholderDNS: placeholderDNS, outlivesClient: outlivesClient) {
                _ = finish(Self.result($0))
            }
        }
    }

    func stop() async throws(Failure) {
        try await call(timeout: .seconds(30)) { helper, finish in
            helper.stop { _ = finish(.success(())) }
        }
    }

    /// A connected controller socket, now owned by the caller.
    func openController() async throws(Failure) -> Int32 {
        try await call(timeout: .seconds(10)) { helper, finish in
            helper.openController { handle, failure in
                guard let handle else {
                    _ = finish(
                        .failure(failure.map { .helper(ProxyHelperFailure(decoding: $0)) } ?? .unavailable))
                    return
                }
                let descriptor = dup(handle.fileDescriptor)
                guard descriptor >= 0 else {
                    _ = finish(.failure(.unavailable))
                    return
                }
                if !finish(.success(descriptor)) { Darwin.close(descriptor) }
            }
        }
    }

    // MARK: - Plumbing

    private static func result(_ failure: Data?) -> Result<Void, Failure> {
        failure.map { .failure(.helper(ProxyHelperFailure(decoding: $0))) } ?? .success(())
    }

    /// The reply, error handler or deadline answers, once; `finish` says whether it was first.
    private func call<Value: Sendable>(
        timeout: Duration,
        _ send: (any ProxyHelperXPC, @escaping @Sendable (Result<Value, Failure>) -> Bool) -> Void
    ) async throws(Failure) -> Value {
        let connection = current().connection
        let result: Result<Value, Failure> = await withCheckedContinuation { continuation in
            let reply = Reply(continuation)
            reply.arm(timeout: timeout, failing: .failure(.unavailable))
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                _ = reply.finish(.failure(.unavailable))
            }
            guard let helper = proxy as? any ProxyHelperXPC else {
                _ = reply.finish(.failure(.unavailable))
                return
            }
            send(helper) { reply.finish($0) }
        }
        return try result.get()
    }

    private func current() -> Line {
        line.withLock { line in
            if let line { return line }
            let created = Line(makeConnection())
            line = created
            return created
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = connector()
        connection.remoteObjectInterface = ProxyHelperWire.helperInterface()
        connection.exportedInterface = ProxyHelperWire.clientInterface()
        connection.exportedObject = Receiver(onStatus: onStatus)
        connection.setCodeSigningRequirement(requirement)
        connection.interruptionHandler = { [onInterruption] in onInterruption() }
        let identifier = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in self?.forget(connection: identifier) }
        connection.activate()
        return connection
    }

    /// An invalidated connection never works again, so the next call makes a new one.
    private func forget(connection identifier: ObjectIdentifier) {
        line.withLock { line in
            if let current = line, ObjectIdentifier(current.connection) == identifier { line = nil }
        }
    }

    private final class Receiver: NSObject, ProxyHelperClientXPC {
        private let onStatus: @Sendable (ProxyHelperStatus) -> Void

        init(onStatus: @escaping @Sendable (ProxyHelperStatus) -> Void) {
            self.onStatus = onStatus
        }

        func helperStatusDidChange(_ status: Data) {
            guard let status = try? JSONDecoder().decode(ProxyHelperStatus.self, from: status) else { return }
            onStatus(status)
        }
    }

    private final class Reply<Value: Sendable>: Sendable {
        private let state: Mutex<(CheckedContinuation<Value, Never>?, Task<Void, Never>?)>

        init(_ continuation: CheckedContinuation<Value, Never>) {
            state = Mutex((continuation, nil))
        }

        func arm(timeout: Duration, failing failure: Value) {
            let deadline = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                _ = self?.finish(failure)
            }
            state.withLock { $0.1 = deadline }
        }

        func finish(_ value: Value) -> Bool {
            let (continuation, deadline) = state.withLock { state in
                defer { state = (nil, nil) }
                return state
            }
            deadline?.cancel()
            guard let continuation else { return false }
            continuation.resume(returning: value)
            return true
        }
    }
}
