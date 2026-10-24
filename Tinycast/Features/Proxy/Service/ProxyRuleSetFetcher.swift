import Foundation

/// Reads the first bytes of a rule-set link, which is enough to tell its format and kind.
enum ProxyRuleSetFetcher {
    enum Failure: Error, Equatable {
        case badLink
        case status(Int)
        case unreachable(String)
    }

    @concurrent
    static func sample(of link: String, proxyPort: Int?) async throws -> (data: Data, isComplete: Bool) {
        guard let url = URL(string: link) else { throw Failure.badLink }
        let session = ProxyURLSession.make(proxyPort: proxyPort, timeout: 20)
        defer { session.invalidateAndCancel() }
        let limit = ProxyRuleSetDetection.sampleLength
        var request = URLRequest(url: url)
        request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-\(limit - 1)", forHTTPHeaderField: "Range")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw Failure.status(status) }
            var data = Data()
            data.reserveCapacity(limit)
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit { return (data, false) }
            }
            return (data, true)
        } catch let failure as Failure {
            throw failure
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.unreachable(error.localizedDescription)
        }
    }
}
