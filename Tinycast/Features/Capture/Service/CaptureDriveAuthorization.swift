import Foundation
import Network
import Security

@MainActor
enum CaptureDriveAuthorization {
    private enum Event: Sendable { case ready(UInt16), code(String) }

    static func connect(
        destination: CaptureUploadDestination, clientSecret: String,
        open: @escaping @MainActor @Sendable (URL) -> Bool
    ) async throws -> CaptureUploadCredential {
        let destination = try destination.validated()
        let verifier = try random(), state = try random()
        let (code, redirect) = try await receive(state: state) { redirect in
            open(
                CaptureDriveService.authorization(
                    client: destination.clientID, redirect: redirect,
                    verifier: verifier, state: state))
        }
        var fields = [
            "client_id": destination.clientID, "code": code, "code_verifier": verifier,
            "redirect_uri": redirect.absoluteString, "grant_type": "authorization_code"
        ]
        if !clientSecret.isEmpty { fields["client_secret"] = clientSecret }
        let (data, response) = try await CaptureUploadTransport { _ in }.send(
            CaptureDriveService.tokenRequest(fields))
        try Task.checkCancellation()
        let token = try CaptureDriveService.token(data, response: response, refreshRequired: true)
        return .init(secret: token, clientSecret: clientSecret)
    }

    static func receive(
        state: String, timeout: Duration = .seconds(300),
        open: @escaping @MainActor @Sendable (URL) -> Bool
    ) async throws -> (String, URL) {
        let listener = try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: "127.0.0.1", port: .any))
        ).newConnectionLimit(8)
        let (events, continuation) = AsyncThrowingStream<Event, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(8))
        defer { continuation.finish() }
        listener.onStateUpdate { listener, status in
            if status == .ready, let port = listener.port { continuation.yield(.ready(port.rawValue)) }
            if case .failed = status { continuation.finish(throwing: CaptureUploadError.authorization) }
        }
        return try await withThrowingTaskGroup(of: (String, URL).self) { group in
            defer { group.cancelAll() }
            group.addTask {
                try await listener.run { connection in
                    do {
                        let code = try await request(connection, state: state)
                        if let code { continuation.yield(.code(code)) }
                    } catch is CancellationError { throw CancellationError() } catch {
                        continuation.finish(throwing: CaptureUploadError.authorization)
                    }
                }
                throw CaptureUploadError.authorization
            }
            group.addTask { try await response(events, open: open) }
            group.addTask {
                try await Task.sleep(for: timeout); throw CaptureUploadError.authorization
            }
            do {
                guard let result = try await group.next() else { throw CaptureUploadError.authorization }
                try Task.checkCancellation()
                return result
            } catch {
                try Task.checkCancellation()
                throw error
            }
        }
    }

    private static func response(
        _ events: AsyncThrowingStream<Event, Error>, open: @escaping @MainActor @Sendable (URL) -> Bool
    ) async throws -> (String, URL) {
        var redirect: URL?
        for try await event in events {
            try Task.checkCancellation()
            switch event {
            case .ready(let port):
                let url = URL(string: "http://127.0.0.1:\(port)/oauth/capture")!
                redirect = url
                guard open(url) else { throw CaptureUploadError.authorization }
            case .code(let code):
                guard let redirect else { throw CaptureUploadError.authorization }
                return (code, redirect)
            }
        }
        throw CancellationError()
    }

    nonisolated private static func request(
        _ connection: NetworkConnection<TCP>, state: String
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                var data = Data()
                while data.count <= 8192 {
                    let part = try await connection.receive(atLeast: 1, atMost: 8193 - data.count)
                    data.append(part.content)
                    if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
                    if part.metadata.endOfStream { return nil }
                }
                guard data.count <= 8192, let text = String(data: data, encoding: .utf8),
                    let line = text.components(separatedBy: "\r\n").first
                else { return nil }
                let parts = line.split(separator: " ")
                guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1" else { return nil }
                let result = Result { try CaptureDriveService.callback(String(parts[1]), state: state) }
                let valid = (try? result.get()) != nil
                let body =
                    valid
                    ? String(localized: "Sign-in received. You can close this tab and return to Tinycast.")
                    : String(localized: "Sign-in was not accepted.")
                let response =
                    "HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\n"
                    + "Content-Type: text/plain; charset=utf-8\r\n"
                    + "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
                    + body
                try await connection.send(Data(response.utf8), endOfStream: true)
                return try result.get()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3)); return nil
            }
            guard let result = try await group.next() else { return nil }
            return result
        }
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CaptureUploadError.authorization
        }
        return CaptureDriveService.base64(Data(bytes))
    }
}
