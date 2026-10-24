import Foundation

/// Fetches mihomo's releases on a private session, through the core while it runs.
enum ProxyCoreDownloader {
    enum Event: Sendable {
        case progress(received: Int64, expected: Int64)
        case finished(Data)
    }

    /// The release `feed` names, as GitHub's `releases/latest` endpoint describes it.
    @concurrent
    static func release(
        from feed: URL, architecture: ReleaseArchitecture, proxyPort: Int?
    ) async throws -> ProxyCoreRelease {
        let session = session(proxyPort: proxyPort)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: feed)
        request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw failure(from: error)
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try ProxyCoreRelease.parse(data, architecture: architecture)
        case 403, 429: throw ProxyCoreUpdateFailure.rateLimited
        case 404: throw ProxyCoreUpdateFailure.noRelease
        case let status: throw ProxyCoreUpdateFailure.unreachable("HTTP \(status)")
        }
    }

    /// Cancelling the consuming task cancels the transfer and tears the session down with it.
    static func download(
        _ release: ProxyCoreRelease, proxyPort: Int?
    ) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let delegate = Delegate(expected: release.assetSize, events: continuation)
            let session = session(proxyPort: proxyPort, delegate: delegate)
            var request = URLRequest(url: release.assetURL)
            request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                // A session holds its delegate until invalidated, so this is what breaks the cycle.
                session.finishTasksAndInvalidate()
            }
            task.resume()
        }
    }

    /// Cacheless, never `URLSession.shared`, so the installed binary is the only copy on disk.
    private static func session(proxyPort: Int?, delegate: (any URLSessionDelegate)? = nil) -> URLSession {
        ProxyURLSession.make(proxyPort: proxyPort, timeout: 60, delegate: delegate)
    }

    fileprivate static func failure(from error: any Error) -> any Error {
        guard let error = error as? URLError else { return error }
        if error.code == .cancelled { return CancellationError() }
        return ProxyCoreUpdateFailure.unreachable(error.localizedDescription)
    }
}

/// Every stored property is immutable and `Sendable`; only `NSObject` keeps it from being checked.
private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let expected: Int64
    private let events: AsyncThrowingStream<ProxyCoreDownloader.Event, any Error>.Continuation

    init(expected: Int64, events: AsyncThrowingStream<ProxyCoreDownloader.Event, any Error>.Continuation) {
        self.expected = expected
        self.events = events
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        events.yield(.progress(received: totalBytesWritten, expected: total))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            events.finish(throwing: ProxyCoreUpdateFailure.unreachable("HTTP \(status)"))
            return
        }
        // The file is unlinked the moment this returns, so it has to be read here.
        do {
            events.yield(.finished(try Data(contentsOf: location)))
            events.finish()
        } catch {
            events.finish(throwing: ProxyCoreUpdateFailure.storage(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        events.finish(throwing: ProxyCoreDownloader.failure(from: error))
    }
}
