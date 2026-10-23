import Foundation

/// Opens one connection through the mixed port, and reads from the core's log how it was routed.
enum ProxyProbeRunner {
    enum Failure: Error, Equatable {
        case unreachable
        /// The core logged nothing about the connection in time.
        case noRecord
    }

    static let timeout = Duration.seconds(5)

    @concurrent
    static func run(
        _ destination: ProxyProbe.Destination, api: ProxyAPIService, port: Int
    ) async throws -> ProxyProbe.Outcome {
        let socket = ProxySocket()
        let localPort: Int
        do {
            let connected = try ProxySocket.connect(loopbackPort: port)
            try socket.adopt(connected.descriptor)
            localPort = connected.localPort
        } catch {
            throw Failure.unreachable
        }
        defer { socket.close() }
        socket.setTimeout(timeout)
        return try await withThrowingTaskGroup(of: ProxyProbe.Outcome?.self) { group in
            group.addTask {
                for try await record in api.logs(level: "info") {
                    let outcome = ProxyProbe.outcome(
                        of: record.payload, sourcePort: localPort, destination: destination)
                    if let outcome { return outcome }
                }
                return nil
            }
            group.addTask {
                // The log stream must be open before the core routes the connection it reports on.
                try await Task.sleep(for: .milliseconds(300))
                let request = "CONNECT \(destination.address) HTTP/1.1\r\nHost: \(destination.address)\r\n\r\n"
                do {
                    try socket.write(Data(request.utf8))
                } catch {
                    throw Failure.unreachable
                }
                try await Task.sleep(for: timeout)
                return nil
            }
            let first = try await group.next()
            group.cancelAll()
            guard case .some(.some(let outcome)) = first else { throw Failure.noRecord }
            return outcome
        }
    }
}
