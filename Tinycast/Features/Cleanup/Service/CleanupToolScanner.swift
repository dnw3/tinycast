import Foundation

/// Finds the installed tools whose stores can be cleaned, and runs their own cleanup commands.
nonisolated enum CleanupToolScanner {
    private static let probeTimeout: TimeInterval = 15

    static func discover(_ environment: CleanupScanner.Environment) async -> [CleanupItem] {
        await withTaskGroup(of: [CleanupItem].self) { group in
            for tool in CleanupTool.allCases {
                group.addTask { await items(for: tool, environment: environment) }
            }
            var found: [CleanupItem] = []
            for await items in group { found += items }
            let order = CleanupTool.allCases.map(\.target)
            return found.sorted { (order.firstIndex(of: $0.match.target) ?? 0) < (order.firstIndex(of: $1.match.target) ?? 0) }
        }
    }

    /// Simulator and Time Machine tools sit at fixed system paths; the rest come from the shell.
    static func locate(_ tool: CleanupTool) async -> URL? {
        switch tool {
        case .simulators:
            let developer = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
                ?? "/Applications/Xcode.app/Contents/Developer"
            let simctl = developer + "/usr/bin/simctl"
            return FileManager.default.isExecutableFile(atPath: simctl) ? URL(fileURLWithPath: simctl) : nil
        case .localSnapshots:
            return URL(fileURLWithPath: "/usr/bin/tmutil")
        default:
            return await ExecutableLocator.locate(tool.executable)
        }
    }

    /// Runs one item's command; nil when the tool reported success.
    static func run(_ item: CleanupItem) async -> CleanupFailure? {
        guard let tool = CleanupTool(target: item.match.target) else { return .refused(.notInCatalog) }
        guard let executable = await locate(tool) else { return .toolMissing }
        let invocations: [[String]]
        if tool == .localSnapshots {
            invocations = item.match.captures.compactMap { tool.arguments(snapshot: $0) }
        } else {
            invocations = tool.arguments().map { [$0] } ?? []
        }
        guard !invocations.isEmpty else { return .refused(.notInCatalog) }
        for arguments in invocations {
            guard !Task.isCancelled else { return .cancelled }
            do {
                let result = try await ToolRunner.run(
                    executable, arguments, timeout: 600,
                    environment: ExecutableLocator.environment(running: executable))
                guard result.succeeded else { return .toolFailed(result.tail) }
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .toolMissing
            }
        }
        return nil
    }

    // MARK: - Probes

    private static func items(for tool: CleanupTool, environment: CleanupScanner.Environment) async -> [CleanupItem] {
        guard let executable = await locate(tool) else { return [] }
        let home = environment.home
        switch tool {
        case .homebrew:
            let cache = home + "/Library/Caches/Homebrew"
            return await measured(tool, path: cache, name: "Homebrew", upperBound: true)
        case .pnpm:
            guard let store = await output(executable, ["store", "path"])?.firstLine else { return [] }
            return await measured(tool, path: store, name: "pnpm", upperBound: true)
        case .goBuild:
            guard let cache = await output(executable, ["env", "GOCACHE"])?.firstLine else { return [] }
            return await measured(tool, path: cache, name: "Go", upperBound: false)
        case .goModules:
            guard let cache = await output(executable, ["env", "GOMODCACHE"])?.firstLine else { return [] }
            return await measured(tool, path: cache, name: "Go", upperBound: false)
        case .simulators:
            guard let json = await output(executable, ["list", "devices", "unavailable", "-j"]),
                let data = json.data(using: .utf8)
            else { return [] }
            let devices = CleanupTool.unavailableDevices(fromJSON: data)
            guard !devices.isEmpty else { return [] }
            let root = home + "/Library/Developer/CoreSimulator/Devices"
            var bytes: Int64 = 0
            for device in devices {
                bytes += (try? DiskUsageScanner.measure(root + "/" + device.udid))?.bytes ?? 0
            }
            var item = makeItem(tool, path: root, name: "simctl", captures: devices.map(\.udid))
            item.size = bytes
            return [item]
        case .docker:
            guard let df = await output(executable, ["system", "df", "--format", "{{json .}}"]),
                let bytes = CleanupTool.dockerReclaimable(fromOutput: df), bytes > 0
            else { return [] }
            var item = makeItem(tool, path: "tool:docker", name: "Docker", captures: [])
            item.size = bytes
            return [item]
        case .localSnapshots:
            guard let listing = await output(executable, ["listlocalsnapshots", "/"]) else { return [] }
            let removable = CleanupTool.removableSnapshots(fromListing: listing)
            guard !removable.isEmpty else { return [] }
            var item = makeItem(tool, path: "tool:localSnapshots", name: "Time Machine", captures: removable)
            item.size = 0
            item.isSizeUnknown = true
            return [item]
        }
    }

    private static func measured(
        _ tool: CleanupTool, path: String, name: String, upperBound: Bool
    ) async -> [CleanupItem] {
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix("/"), let measurement = try? DiskUsageScanner.measure(standardized),
            measurement.bytes > 0
        else { return [] }
        var item = makeItem(tool, path: standardized, name: name, captures: [])
        item.size = measurement.bytes
        item.isPartial = measurement.isPartial
        item.isUpperBound = upperBound
        return [item]
    }

    private static func makeItem(_ tool: CleanupTool, path: String, name: String, captures: [String]) -> CleanupItem {
        CleanupItem(
            path: path,
            match: CleanupMatch(target: tool.target, pattern: CleanupPattern(""), captures: captures, isContentsChild: false),
            name: name, modified: nil, protection: .removable)
    }

    private static func output(_ executable: URL, _ arguments: [String]) async -> String? {
        guard let result = try? await ToolRunner.run(
            executable, arguments, timeout: probeTimeout,
            environment: ExecutableLocator.environment(running: executable)),
            result.succeeded
        else { return nil }
        return result.output
    }
}

private extension String {
    var firstLine: String? {
        let line = split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return line?.isEmpty == false ? line : nil
    }
}
