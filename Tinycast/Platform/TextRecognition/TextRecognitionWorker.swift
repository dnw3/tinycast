import Foundation

/// Runs one `TextRecognitionHelper` per item, so Vision's allocations leave with the child process.
nonisolated enum TextRecognitionWorker {
    enum Failure: LocalizedError {
        case recognition, outputLimit, foreground
        var errorDescription: String? {
            switch self {
            case .recognition:
                String(localized: "Text recognition did not finish. Try a smaller region or retry.")
            case .outputLimit:
                String(localized: "Too much text was returned. Select a smaller region and retry.")
            case .foreground:
                String(
                    localized: "Background removal did not finish. Try a clearer subject or a smaller image.")
            }
        }
    }

    private static let maximumOutputBytes = 1_048_576
    private static let readSize = 4096
    /// Blocking pipe reads stay off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.tinycast.text-recognition", qos: .background, attributes: .concurrent)

    static func extract(
        at url: URL, isPDF: Bool,
        executable: URL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/TextRecognitionHelper"),
        timeout: Duration = .seconds(60)
    ) async throws -> String {
        try await run(at: url, mode: isPDF ? "pdf" : "image", executable: executable, timeout: timeout)
    }

    static func recognize(
        at url: URL,
        executable: URL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/TextRecognitionHelper"),
        timeout: Duration = .seconds(90)
    ) async throws -> TextRecognitionResult {
        let json = try await run(at: url, mode: "capture", executable: executable, timeout: timeout)
        return try JSONDecoder().decode(TextRecognitionResult.self, from: Data(json.utf8))
    }

    static func foreground(
        at url: URL,
        executable: URL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/TextRecognitionHelper")
    ) async throws -> URL {
        do {
            guard
                try await run(at: url, mode: "foreground", executable: executable, timeout: .seconds(90))
                    == "ok"
            else { throw Failure.foreground }
            return url.appendingPathExtension("mask.png")
        } catch is CancellationError {
            throw CancellationError()
        } catch { throw Failure.foreground }
    }

    private static func run(
        at url: URL, mode: String, executable: URL, timeout: Duration
    ) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [mode, url.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = mode == "image" || mode == "pdf" ? .background : .userInitiated
        let completion = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = {
            completion.continuation.yield($0.terminationStatus)
            completion.continuation.finish()
        }
        defer {
            process.terminationHandler = nil
            completion.continuation.finish()
        }
        do { try process.run() } catch { throw Failure.recognition }
        // Exit observation must survive caller cancellation until Foundation reaps the child.
        let exitTask = Task.detached(priority: .userInitiated) {
            for await status in completion.stream { return status }
            return Int32(-1)
        }
        // Cancellation can land between the check above and the launch, which nothing else catches.
        if Task.isCancelled { terminate(process) }
        let deadline = Task.detached(priority: .userInitiated) {
            do { try await Task.sleep(for: timeout) } catch { return }
            terminate(process)
        }
        let (result, status) = await withTaskCancellationHandler {
            let result = await withCheckedContinuation { continuation in
                queue.async(qos: mode == "image" || mode == "pdf" ? .background : .userInitiated) {
                    continuation.resume(returning: collect(reading: output))
                }
            }
            if case .failure = result { terminate(process) }
            return (result, await exitTask.value)
        } onCancel: {
            terminate(process)
        }
        deadline.cancel()
        try Task.checkCancellation()
        if case .failure(let failure) = result { throw failure }
        guard status == 0 else { throw Failure.recognition }
        return try result.get()
    }

    private static func collect(reading output: Pipe) -> Result<String, Failure> {
        let reader = output.fileHandleForReading
        defer {
            try? reader.close()
        }
        var data = Data()
        do {
            while let chunk = try reader.read(upToCount: readSize), !chunk.isEmpty {
                data.append(chunk)
                if data.count > maximumOutputBytes { return .failure(.outputLimit) }
            }
        } catch {
            return .failure(.recognition)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(.recognition)
        }
        return .success(text)
    }

    private static func terminate(_ process: Process) {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
