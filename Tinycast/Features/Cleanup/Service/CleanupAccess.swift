import Darwin
import Foundation

/// The process-wide reads a scan and a run share, so the two can never disagree about them.
nonisolated enum CleanupAccess {
    /// `appNames` is keyed by lowercased bundle ID: the launcher's own index, read on the main actor.
    static func environment(
        exclusions: [String], appNames: [String: String], now: Date = Date()
    ) -> CleanupScanner.Environment {
        let home = NSHomeDirectory()
        return CleanupScanner.Environment(
            home: home, resolvedHome: CleanupScanner.resolvedPath(home) ?? home,
            hasFullDiskAccess: Permissions.hasFullDiskAccess(), exclusions: exclusions, now: now,
            appName: { appNames[$0.lowercased()] })
    }

    /// GUI apps come from `RunningAppsMonitor`; command-line tools are read here by executable name.
    static func runtime(runningBundleIDs: Set<String>) -> CleanupRuntime {
        let processes = processSnapshot()
        return CleanupRuntime(
            runningBundleIDs: runningBundleIDs, runningProcesses: processes.names,
            workingDirectories: processes.workingDirectories)
    }

    struct ProcessSnapshot: Sendable {
        var names: Set<String> = []
        var workingDirectories: Set<String> = []
    }

    /// Bytes free on the home volume, excluding purgeable space so a snapshot cannot inflate a gain.
    static func availableCapacity() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// Executable names, lowercased, and working directories of this user's processes; another
    /// user's are unreadable.
    static func processSnapshot() -> ProcessSnapshot {
        let capacity = Int(proc_listallpids(nil, 0)) + 32
        guard capacity > 32 else { return ProcessSnapshot() }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { buffer in
            Int(proc_listallpids(buffer.baseAddress, Int32(buffer.count)))
        }
        guard count > 0 else { return ProcessSnapshot() }
        var snapshot = ProcessSnapshot()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            let length = path.withUnsafeMutableBufferPointer { buffer in
                proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
            }
            if length > 0 {
                let full = path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                snapshot.names.insert((full as NSString).lastPathComponent.lowercased())
            }
            if let directory = workingDirectory(of: pid), directory != "/" {
                snapshot.workingDirectories.insert(directory)
            }
        }
        return snapshot
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            let bytes = raw.bindMemory(to: CChar.self)
            guard let base = bytes.baseAddress, base.pointee != 0 else { return nil }
            return String(cString: base)
        }
    }
}
