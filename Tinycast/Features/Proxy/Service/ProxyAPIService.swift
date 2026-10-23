import Foundation

/// The core's REST API, one connection per call, so a cancelled call never wedges the next one.
struct ProxyAPIService: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case unreachable
        case rejected(status: Int, message: String)
        case malformed
        case timedOut
    }

    /// A connected socket: by path to a user-level core, or handed over by the helper.
    let connect: @Sendable () async throws -> Int32

    static let bodyLimit = 64 << 20

    static func unixSocket(at path: String) -> ProxyAPIService {
        ProxyAPIService { try ProxySocket.connect(path: path) }
    }

    /// The response body of a successful call; a status of 400 or more throws the core's message.
    @concurrent
    func send(_ request: ProxyHTTP.Request, timeout: Duration = .seconds(10)) async throws -> Data {
        let socket = ProxySocket()
        return try await withTaskCancellationHandler {
            do {
                try socket.adopt(await connect())
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw Failure.unreachable
            }
            defer { socket.close() }
            socket.setTimeout(timeout)
            let result = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(
                        returning: Result { () throws(Failure) in try Self.exchange(request, on: socket) })
                }
            }
            try Task.checkCancellation()
            return try result.get()
        } onCancel: {
            socket.interrupt()
        }
    }

    func decode<Value: Decodable>(
        _ type: Value.Type, from request: ProxyHTTP.Request, timeout: Duration = .seconds(10)
    ) async throws -> Value {
        let body = try await send(request, timeout: timeout)
        guard let value = try? JSONDecoder().decode(Value.self, from: body) else { throw Failure.malformed }
        return value
    }

    /// Records of a streaming endpoint as they arrive, until the consumer stops iterating.
    func lines(_ request: ProxyHTTP.Request) -> AsyncThrowingStream<Data, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        let socket = ProxySocket()
        continuation.onTermination = { _ in socket.interrupt() }
        Task.detached { [connect] in
            do {
                try socket.adopt(await connect())
            } catch {
                continuation.finish(throwing: error is CancellationError ? error : Failure.unreachable)
                return
            }
            DispatchQueue.global(qos: .utility).async {
                defer { socket.close() }
                do {
                    try Self.stream(request, on: socket) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return stream
    }

    // MARK: - Endpoints

    func version() async throws -> String {
        try await decode(ProxyAPI.Version.self, from: .get("/version")).version
    }

    func proxies() async throws -> [String: ProxyAPI.Proxy] {
        try await decode(ProxyAPI.Proxies.self, from: .get("/proxies")).proxies
    }

    func providers() async throws -> [String: ProxyAPI.Provider] {
        try await decode(ProxyAPI.Providers.self, from: .get("/providers/proxies")).providers
    }

    func ruleProviders() async throws -> [String: ProxyAPI.RuleProvider] {
        try await decode(ProxyAPI.RuleProviders.self, from: .get("/providers/rules")).providers
    }

    func select(_ option: String, in group: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": option])
        _ = try await send(.put("/proxies/" + ProxyHTTP.segment(group), json: body))
    }

    /// Applies a whole config in place; `force` is what lets port and LAN changes take effect.
    func reload(_ document: Data) async throws {
        guard let payload = String(bytes: document, encoding: .utf8) else { throw Failure.malformed }
        let body = try JSONSerialization.data(withJSONObject: ["path": "", "payload": payload])
        _ = try await send(.put("/configs?force=true", json: body), timeout: .seconds(120))
    }

    /// `global` sends everything through the `GLOBAL` group; a reload restores the config's mode.
    func setMode(_ mode: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["mode": mode])
        _ = try await send(.patch("/configs", json: body))
    }

    /// Milliseconds by node for every node that answered within `timeout`.
    func testGroup(_ group: String, url: String, timeout: Duration) async throws -> [String: Int] {
        let query = ProxyHTTP.query([("url", url), ("timeout", String(timeout.milliseconds))])
        return try await decode(
            [String: Int].self, from: .get("/group/\(ProxyHTTP.segment(group))/delay?\(query)"),
            timeout: timeout + .seconds(5))
    }

    /// Nodes from a source answer only under their provider; `/proxies` knows groups alone.
    func testNode(_ node: String, provider: String, url: String, timeout: Duration) async throws -> Int {
        let query = ProxyHTTP.query([("url", url), ("timeout", String(timeout.milliseconds))])
        let target =
            "/providers/proxies/\(ProxyHTTP.segment(provider))/\(ProxyHTTP.segment(node))/healthcheck?\(query)"
        return try await decode(ProxyAPI.Delay.self, from: .get(target), timeout: timeout + .seconds(5)).delay
    }

    /// Tests every node a source holds against the core's own health-check URL.
    func testProvider(_ name: String) async throws {
        let target = "/providers/proxies/\(ProxyHTTP.segment(name))/healthcheck"
        _ = try await send(.get(target), timeout: .seconds(60))
    }

    /// Returns once the source has been fetched again, or has failed to be.
    func updateProvider(_ name: String) async throws {
        _ = try await send(.put("/providers/proxies/" + ProxyHTTP.segment(name)), timeout: .seconds(120))
    }

    /// Returns once the rule set has been downloaded again, or has failed to be.
    func updateRuleProvider(_ name: String) async throws {
        _ = try await send(.put("/providers/rules/" + ProxyHTTP.segment(name)), timeout: .seconds(120))
    }

    func connections() async throws -> [ProxyAPI.Connection] {
        try await decode(ProxyAPI.Connections.self, from: .get("/connections")).connections
    }

    func closeConnection(_ id: String) async throws {
        _ = try await send(.delete("/connections/" + ProxyHTTP.segment(id)))
    }

    func traffic() -> some AsyncSequence<ProxyAPI.Traffic, any Error> {
        lines(.get("/traffic")).compactMap { try? JSONDecoder().decode(ProxyAPI.Traffic.self, from: $0) }
    }

    /// What the core logs from now on, at `level` or above, whatever level its config writes.
    func logs(level: String) -> some AsyncSequence<ProxyAPI.LogRecord, any Error> {
        lines(.get("/logs?level=" + level)).compactMap {
            try? JSONDecoder().decode(ProxyAPI.LogRecord.self, from: $0)
        }
    }

    // MARK: - Blocking I/O

    private static func exchange(
        _ request: ProxyHTTP.Request, on socket: ProxySocket
    ) throws(Failure) -> Data {
        var parser = ProxyHTTP.ResponseParser()
        var head: ProxyHTTP.Head?
        var body = Data()
        try transfer(request, on: socket, parser: &parser) { event throws(Failure) in
            switch event {
            case .head(let received): head = received
            case .body(let data):
                body.append(data)
                guard body.count <= bodyLimit else { throw .malformed }
            case .end: return false
            }
            return true
        }
        guard let head else { throw .malformed }
        guard head.status < 400 else {
            let message = (try? JSONDecoder().decode(ProxyAPI.Message.self, from: body))?.message ?? ""
            throw .rejected(status: head.status, message: message)
        }
        return body
    }

    private static func stream(
        _ request: ProxyHTTP.Request, on socket: ProxySocket, yield: (Data) -> Void
    ) throws(Failure) {
        var parser = ProxyHTTP.ResponseParser()
        var lines = ProxyHTTP.LineSplitter()
        try transfer(request, on: socket, parser: &parser) { event throws(Failure) in
            switch event {
            case .head(let head):
                guard head.status < 400 else { throw .rejected(status: head.status, message: "") }
            case .body(let data): lines.consume(data).forEach(yield)
            case .end: return false
            }
            return true
        }
    }

    /// Writes the request, then feeds the parser until the handler or the connection ends it.
    private static func transfer(
        _ request: ProxyHTTP.Request, on socket: ProxySocket, parser: inout ProxyHTTP.ResponseParser,
        handle: (ProxyHTTP.Event) throws(Failure) -> Bool
    ) throws(Failure) {
        do {
            try socket.write(request.bytes)
            var buffer = [UInt8](repeating: 0, count: 64 << 10)
            while true {
                let count = try socket.read(into: &buffer)
                let events = try count == 0 ? parser.finish() : parser.consume(buffer[..<count])
                for event in events {
                    guard try handle(event) else { return }
                }
                if count == 0 { throw Failure.malformed }
            }
        } catch let failure as Failure {
            throw failure
        } catch ProxySocket.Failure.timedOut {
            throw .timedOut
        } catch is ProxySocket.Failure {
            throw .unreachable
        } catch {
            throw .malformed
        }
    }
}

extension Duration {
    fileprivate var milliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}
