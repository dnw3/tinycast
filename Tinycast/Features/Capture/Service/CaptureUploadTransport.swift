import Foundation
import Synchronization

final class CaptureUploadTransport: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var data = Data()
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        var task: URLSessionTask?
        var failure: Error?
        var cancelled = false
        var progress = -1.0
    }
    private let state = Mutex(State())
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func upload(_ request: URLRequest, file: URL, configuration: URLSessionConfiguration? = nil) async throws
        -> (Data, HTTPURLResponse) {
        try await execute(request, file: file, configuration: configuration)
    }

    func send(_ request: URLRequest, configuration: URLSessionConfiguration? = nil) async throws -> (Data, HTTPURLResponse) {
        try await execute(request, file: nil, configuration: configuration)
    }

    private func execute(_ request: URLRequest, file: URL?, configuration: URLSessionConfiguration?) async throws
        -> (Data, HTTPURLResponse) {
        let config = configuration ?? .ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task: URLSessionTask = if let file {
                    session.uploadTask(with: request, fromFile: file)
                } else { session.dataTask(with: request) }
                let cancelled = state.withLock { state in
                    guard !state.cancelled else { return true }
                    state.continuation = continuation; state.task = task
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) } else { task.resume() }
            }
        } onCancel: {
            let task = self.state.withLock { $0.cancelled = true; return $0.task }
            task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? { nil }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded = state.withLock { state in
            guard state.data.count + data.count <= 65_536 else {
                state.failure = CaptureUploadError.responseLimit
                return true
            }
            state.data.append(data)
            return false
        }
        if exceeded { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let value = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        let report = state.withLock { state in
            guard value - state.progress >= 0.01 || value == 1 else { return false }
            state.progress = value
            return true
        }
        if report { progress(value) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = state.withLock { state -> (CheckedContinuation<(Data, HTTPURLResponse), Error>?, Data, Error?) in
            defer { state.continuation = nil; state.task = nil; state.data = Data() }
            return (state.continuation, state.data, state.cancelled ? CancellationError() : state.failure ?? error)
        }
        if let error = result.2 { result.0?.resume(throwing: error) } else if let response = task.response as? HTTPURLResponse {
            result.0?.resume(returning: (result.1, response))
        } else { result.0?.resume(throwing: CaptureUploadError.response) }
    }
}
