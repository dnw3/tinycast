import Foundation

/// Drained as it arrives, so a tool outwriting the pipe buffer cannot wedge.
enum ToolRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }

        /// The tail, which is where a tool puts the actual error.
        var tail: String {
            let lines = output.split(separator: "\n").suffix(8)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? String(localized: "no output") : text
        }
    }

    /// A nil `timeout` never kills: the tool may be waiting on a person rather than wedged.
    static func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval? = 120,
        environment: [String: String]? = nil, currentDirectory: URL? = nil
    ) async throws -> Result {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        // A tool that prompts would otherwise wait forever on a pipe nobody writes to.
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = OutputCollector()
        pipe.fileHandleForReading.readabilityHandler = { collector.absorb($0.availableData) }

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await wait(for: process, pipe: pipe, collector: collector, timeout: timeout)
        } onCancel: {
            box.terminate()
        }
    }

    private static func wait(
        for process: Process, pipe: Pipe, collector: OutputCollector, timeout: TimeInterval?
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                collector.absorb((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                continuation.resume(
                    returning: Result(status: finished.terminationStatus, output: collector.text))
            }
            do {
                try process.run()
            } catch {
                // The handler never fires for a process that never started, so resume here instead.
                pipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            guard let timeout else { return }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard process.isRunning else { return }
                process.terminate()
            }
        }
    }
}

/// Lets cancellation reach a process from whatever thread the handler runs on.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) { self.process = process }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Read from the pipe's queue and the termination handler, so the lock is load-bearing.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Latin-1 cannot fail, so other encodings still reach the user.
        return String(bytes: buffer, encoding: .utf8)
            ?? String(bytes: buffer, encoding: .isoLatin1) ?? ""
    }

    /// Buffers bytes, not text: a read landing mid-character would decode to a replacement.
    func absorb(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}
