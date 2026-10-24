import Foundation

/// HTTP/1.1 as the core's controller speaks it over a Unix socket: one request per connection.
enum ProxyHTTP {
    struct Request: Equatable, Sendable {
        var method: String
        /// The path and query, already encoded with `segment(_:)` and `query(_:)`.
        var target: String
        var body: Data?

        static func get(_ target: String) -> Request {
            Request(method: "GET", target: target, body: nil)
        }

        static func put(_ target: String, json body: Data? = nil) -> Request {
            Request(method: "PUT", target: target, body: body)
        }

        static func patch(_ target: String, json body: Data) -> Request {
            Request(method: "PATCH", target: target, body: body)
        }

        static func delete(_ target: String) -> Request {
            Request(method: "DELETE", target: target, body: nil)
        }

        var bytes: Data {
            var head = "\(method) \(target) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
            if let body {
                head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
            } else if method == "PUT" {
                head += "Content-Length: 0\r\n"
            }
            return Data((head + "\r\n").utf8) + (body ?? Data())
        }
    }

    struct Head: Equatable, Sendable {
        var status: Int
        /// Names are lowercased; a repeated header keeps its last value.
        var headers: [String: String]
    }

    enum Event: Equatable, Sendable {
        case head(Head)
        case body(Data)
        case end
    }

    enum ParseError: Error, Equatable {
        case malformed
        case tooLarge
        case truncated
    }

    /// Frames a response as its bytes arrive: by length, by chunks, or until the core closes.
    struct ResponseParser: Sendable {
        private enum State: Sendable {
            case head
            case fixed(remaining: Int)
            case chunkSize
            case chunkData(remaining: Int)
            case chunkEnd
            case trailers
            case untilClose
            case done
        }

        static let headLimit = 64 * 1024

        private var state = State.head
        private var buffer: [UInt8] = []

        init() {}

        mutating func consume(_ bytes: some Sequence<UInt8>) throws(ParseError) -> [Event] {
            buffer.append(contentsOf: bytes)
            var events: [Event] = []
            while let event = try next() { events.append(event) }
            return events
        }

        /// The core closed the connection; only a body that runs until the close may end here.
        mutating func finish() throws(ParseError) -> [Event] {
            switch state {
            case .done: return []
            case .untilClose:
                state = .done
                return [.end]
            default: throw .truncated
            }
        }

        private mutating func next() throws(ParseError) -> Event? {
            switch state {
            case .head:
                guard let end = buffer.firstRange(of: [13, 10, 13, 10]) else {
                    if buffer.count > Self.headLimit { throw .tooLarge }
                    return nil
                }
                let head = try Self.parseHead(buffer[..<end.lowerBound])
                buffer.removeFirst(end.upperBound)
                state = Self.bodyState(after: head)
                return .head(head)
            case .fixed(let remaining):
                if remaining == 0 {
                    state = .done
                    return .end
                }
                guard !buffer.isEmpty else { return nil }
                let count = min(remaining, buffer.count)
                state = .fixed(remaining: remaining - count)
                return .body(take(count))
            case .chunkSize:
                guard let line = takeLine() else {
                    if buffer.count > Self.headLimit { throw .tooLarge }
                    return nil
                }
                let digits = line.split(separator: ";", maxSplits: 1).first ?? ""
                guard let size = Int(digits.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else {
                    throw .malformed
                }
                state = size == 0 ? .trailers : .chunkData(remaining: size)
                return try next()
            case .chunkData(let remaining):
                guard !buffer.isEmpty else { return nil }
                let count = min(remaining, buffer.count)
                state = count == remaining ? .chunkEnd : .chunkData(remaining: remaining - count)
                return .body(take(count))
            case .chunkEnd:
                guard let line = takeLine() else { return nil }
                guard line.isEmpty else { throw .malformed }
                state = .chunkSize
                return try next()
            case .trailers:
                guard let line = takeLine() else { return nil }
                guard line.isEmpty else { return try next() }
                state = .done
                return .end
            case .untilClose:
                guard !buffer.isEmpty else { return nil }
                return .body(take(buffer.count))
            case .done:
                return nil
            }
        }

        private mutating func take(_ count: Int) -> Data {
            defer { buffer.removeFirst(count) }
            return Data(buffer[..<count])
        }

        private mutating func takeLine() -> String? {
            guard let end = buffer.firstRange(of: [13, 10]) else { return nil }
            defer { buffer.removeFirst(end.upperBound) }
            return String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
        }

        private static func parseHead(_ bytes: ArraySlice<UInt8>) throws(ParseError) -> Head {
            guard let text = String(bytes: bytes, encoding: .utf8) else { throw .malformed }
            let lines = text.components(separatedBy: "\r\n")
            let statusLine = lines[0].split(separator: " ", maxSplits: 2)
            guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."), let status = Int(statusLine[1])
            else {
                throw .malformed
            }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { throw .malformed }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
            }
            return Head(status: status, headers: headers)
        }

        private static func bodyState(after head: Head) -> State {
            if head.status == 204 || head.status == 304 || (100..<200).contains(head.status) {
                return .fixed(remaining: 0)
            }
            if head.headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
                return .chunkSize
            }
            if let length = head.headers["content-length"].flatMap({ Int($0) }), length >= 0 {
                return .fixed(remaining: length)
            }
            return .untilClose
        }
    }

    /// Splits a streamed body into the core's newline-delimited JSON records.
    struct LineSplitter: Sendable {
        private var pending: [UInt8] = []

        init() {}

        mutating func consume(_ data: Data) -> [Data] {
            pending.append(contentsOf: data)
            var lines: [Data] = []
            while let newline = pending.firstIndex(of: 10) {
                var line = pending[..<newline]
                if line.last == 13 { line = line.dropLast() }
                if !line.isEmpty { lines.append(Data(line)) }
                pending.removeFirst(newline + 1)
            }
            return lines
        }
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// One path segment; names hold slashes (`route/ai`), spaces and any script.
    static func segment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    static func query(_ items: [(String, String)]) -> String {
        items.map { segment($0.0) + "=" + segment($0.1) }.joined(separator: "&")
    }
}
