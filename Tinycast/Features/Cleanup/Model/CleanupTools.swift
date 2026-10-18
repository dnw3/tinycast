import Foundation

/// Stores a tool manages itself; Tinycast runs the tool's own cleanup and never deletes inside them.
enum CleanupTool: String, CaseIterable, Sendable {
    case homebrew
    case simulators
    case pnpm
    case goBuild
    case goModules
    case docker
    case localSnapshots

    var target: CleanupTargetID {
        switch self {
        case .homebrew: return .homebrewCache
        case .simulators: return .unavailableSimulators
        case .pnpm: return .pnpmStore
        case .goBuild: return .goBuildCache
        case .goModules: return .goModuleCache
        case .docker: return .dockerData
        case .localSnapshots: return .localSnapshots
        }
    }

    init?(target: CleanupTargetID) {
        guard let tool = Self.allCases.first(where: { $0.target == target }) else { return nil }
        self = tool
    }

    /// The executable's file name, located through the user's shell like every other CLI.
    var executable: String {
        switch self {
        case .homebrew: return "brew"
        case .simulators: return "simctl"
        case .pnpm: return "pnpm"
        case .goBuild, .goModules: return "go"
        case .docker: return "docker"
        case .localSnapshots: return "tmutil"
        }
    }

    /// Fixed per tool, so nothing a scan read can widen what runs.
    func arguments(snapshot: String? = nil) -> [String]? {
        switch self {
        case .homebrew: return ["cleanup", "--prune=all"]
        case .simulators: return ["delete", "unavailable"]
        case .pnpm: return ["store", "prune"]
        case .goBuild: return ["clean", "-cache"]
        case .goModules: return ["clean", "-modcache"]
        // No `--volumes`: a volume is a database's data, not a cache.
        case .docker: return ["system", "prune", "--force"]
        case .localSnapshots:
            guard let snapshot, Self.isSnapshotDate(snapshot) else { return nil }
            return ["deletelocalsnapshots", snapshot]
        }
    }

    /// The tool's own process name; a run while it works would race it.
    var ownerProcesses: [String] {
        switch self {
        case .homebrew: return ["brew"]
        case .simulators: return ["simctl", "simulator"]
        case .pnpm: return ["pnpm"]
        case .goBuild, .goModules: return ["go"]
        case .docker: return []
        case .localSnapshots: return ["backupd"]
        }
    }

    // MARK: - Parsing

    /// `2026-10-17-123456`, the only argument shape `deletelocalsnapshots` is ever given.
    static func isSnapshotDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2, parts[3].count == 6
        else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    /// Time Machine's own local snapshots, oldest first, all but the newest; others are left alone.
    static func removableSnapshots(fromListing output: String) -> [String] {
        let prefix = "com.apple.TimeMachine."
        let dates = output.split(separator: "\n").compactMap { line -> String? in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix(prefix), name.hasSuffix(".local") else { return nil }
            let date = String(name.dropFirst(prefix.count).dropLast(".local".count))
            return isSnapshotDate(date) ? date : nil
        }
        return Array(dates.sorted().dropLast())
    }

    /// Unavailable devices from `simctl list devices unavailable -j`, as UDID and name.
    static func unavailableDevices(fromJSON data: Data) -> [(udid: String, name: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let runtimes = root["devices"] as? [String: Any]
        else { return [] }
        var devices: [(String, String)] = []
        for case let list as [[String: Any]] in runtimes.values {
            for device in list {
                guard let udid = device["udid"] as? String, isUDID(udid),
                    (device["isAvailable"] as? Bool) == false
                else { continue }
                devices.append((udid, device["name"] as? String ?? udid))
            }
        }
        return devices.sorted { $0.1 < $1.1 }
    }

    static func isUDID(_ text: String) -> Bool {
        text.count == 36 && text.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    /// Reclaimable bytes from `docker system df --format '{{json .}}'`, one JSON object per line.
    static func dockerReclaimable(fromOutput output: String) -> Int64? {
        var total: Int64 = 0
        var found = false
        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = row["Reclaimable"] as? String,
                let bytes = parseDockerSize(String(text.split(separator: " ").first ?? ""))
            else { continue }
            total += bytes
            found = true
        }
        return found ? total : nil
    }

    /// Docker prints decimal units: "1.2GB", "512.5MB", "0B".
    static func parseDockerSize(_ text: String) -> Int64? {
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, scale) in units where text.hasSuffix(suffix) {
            guard let value = Double(text.dropLast(suffix.count)) else { return nil }
            return Int64(value * scale)
        }
        return nil
    }
}
