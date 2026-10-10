import Foundation

nonisolated enum CaptureWebPWorker {
    static func export(
        document: CaptureDocument, directory: URL, to destination: URL, options: CaptureExportOptions,
        executable: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CaptureWebPHelper"),
        timeout: Duration = .seconds(60)
    ) async throws {
        let size = try options.validatedDimensions(for: document)
        let input = directory.appendingPathComponent("webp-\(UUID())")
        let output = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID()).webp")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try await CaptureWork.run {
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
            let image = try CaptureRenderer.exportImage(document: document, directory: directory,
                size: size, options: options)
            try CaptureWebPInput.write(image, quality: options.quality,
                lossless: options.webPCompression == .lossless, to: input)
        }
        try await run(input: input, output: output, executable: executable, timeout: timeout)
        try Task.checkCancellation()
        guard rename(output.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func run(input: URL, output: URL, executable: URL, timeout: Duration) async throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = [input.path, output.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        let completion = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = {
            completion.continuation.yield($0.terminationStatus)
            completion.continuation.finish()
        }
        defer { process.terminationHandler = nil; completion.continuation.finish() }
        try process.run()
        // Reap the child before cancellation releases its input and output files.
        let exitTask = Task.detached(priority: .userInitiated) {
            for await status in completion.stream { return status }
            return Int32(-1)
        }
        if Task.isCancelled { terminate(process) }
        let deadline = Task.detached(priority: .userInitiated) {
            do { try await Task.sleep(for: timeout) } catch { return }
            terminate(process)
        }
        defer { deadline.cancel() }
        let status = await withTaskCancellationHandler {
            await exitTask.value
        } onCancel: { terminate(process) }
        try Task.checkCancellation()
        guard status == 0 else { throw CaptureRasterError.compressionFailed }
    }

    private static func terminate(_ process: Process) {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
