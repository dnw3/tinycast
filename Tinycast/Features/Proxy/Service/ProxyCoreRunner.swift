import Foundation

/// Runs a core binary: its `-v` and `-t` checks, and the user-level core itself.
enum ProxyCoreRunner {
    struct Rejection: Error, Equatable, Sendable {
        var reason: String
    }

    /// Absent from a build made without `Scripts/fetch-mihomo.sh`.
    static var bundledCore: URL? {
        let core = Bundle.main.bundleURL.appending(path: "Contents/Helpers/mihomo")
        return FileManager.default.isExecutableFile(atPath: core.path) ? core : nil
    }

    /// Nothing inherited: variables such as `SAFE_PATHS` would widen what the core may read.
    static var environment: [String: String] {
        ["HOME": FileManager.default.homeDirectoryForCurrentUser.path]
    }

    /// In a scratch directory, because a check writes the core's cache wherever it runs.
    @concurrent
    static func check(_ document: Data, core: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "tinycast-proxy-check-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let config = scratch.appending(path: "config.json")
        try document.write(to: config)
        let (status, text) = try await run(core, ["-t", "-d", scratch.path, "-f", config.path])
        guard status == 0 else {
            throw Rejection(
                reason: reason(fromCheckOutput: text) ?? text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// What the binary says it is; `-v` prints and exits without touching any directory.
    @concurrent
    static func identify(_ core: URL) async throws -> ProxyCore.Identity {
        let (status, text) = try await run(core, ["-v"])
        guard status == 0, let identity = ProxyCore.Identity(versionOutput: text) else {
            throw Rejection(reason: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return identity
    }

    @concurrent
    private static func run(
        _ core: URL, _ arguments: [String]
    ) async throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = core
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        let text = try await withTaskCancellationHandler {
            let exit = try process.runObservingExit()
            let bytes: Data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(
                        with: Result {
                            defer { exit.wait() }
                            return try output.fileHandleForReading.readToEnd() ?? Data()
                        })
                }
            }
            return String(bytes: bytes, encoding: .utf8) ?? ""
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()
        return (process.terminationStatus, text)
    }

    /// The first error the core logged, or the panic that ended the check.
    static func reason(fromCheckOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("panic: ") { return String(line.dropFirst("panic: ".count)) }
            guard line.contains("level=error"), let start = line.range(of: "msg=\"")?.upperBound else {
                continue
            }
            var message = ""
            var escaped = false
            for character in line[start...] {
                if escaped {
                    message.append(character == "n" ? "\n" : character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    return message
                } else {
                    message.append(character)
                }
            }
            return message
        }
        return nil
    }

    /// Starts the user-level core on its own directory; it writes its log there from scratch.
    static func launch(
        core: URL, directory: URL, socket: String, onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> Process {
        let log = directory.appending(path: "core.log")
        FileManager.default.createFile(
            atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = core
        process.arguments = [
            "-d", directory.path, "-f", directory.appending(path: "config.json").path, "-ext-ctl-unix", socket
        ]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
        return process
    }

    /// The end of the core's log, for a report when it stops on its own.
    static func logTail(in directory: URL, lines: Int = 20) -> String {
        guard let handle = try? FileHandle(forReadingFrom: directory.appending(path: "core.log")) else {
            return ""
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 16_384 ? size - 16_384 : 0)
        let text = (try? handle.readToEnd()).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        return text.split(whereSeparator: \.isNewline).suffix(lines).joined(separator: "\n")
    }
}
