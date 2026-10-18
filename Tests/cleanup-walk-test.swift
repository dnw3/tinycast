import Darwin
import Foundation
import Synchronization

/// Records instead of removing, so a run is observed without the real Trash.
final class RecordingOperations: CleanupFileOperations {
    let removed = Mutex<[String]>([])
    let trashed = Mutex<[String]>([])

    func remove(_ path: String) throws { removed.withLock { $0.append(path) } }
    func trash(_ path: String) throws { trashed.withLock { $0.append(path) } }
    func children(of path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
    func evict(_ path: String) throws { removed.withLock { $0.append("evict:" + path) } }
}

@main
@MainActor
struct CleanupWalkTests {
    static var failures = 0
    static var passes = 0

    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cleanup-walk-\(UUID().uuidString)").path
    static let home = root + "/home"
    static let derivedData = "Library/Developer/Xcode/DerivedData/Proj-abcdefghijklmnopqrstuvwxyzab"

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    // MARK: - Fixtures

    static func write(_ relative: String, bytes: Int = 5_000, base: String = home) {
        let path = base + "/" + relative
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 7, count: bytes))
    }

    static func folder(_ relative: String) {
        try? FileManager.default.createDirectory(
            atPath: home + "/" + relative, withIntermediateDirectories: true)
    }

    static func blocks(_ path: String) -> Int64 {
        var info = stat()
        return lstat(path, &info) == 0 ? Int64(info.st_blocks) * 512 : 0
    }

    static func environment(hasFullDiskAccess: Bool = true) -> CleanupScanner.Environment {
        CleanupScanner.Environment(
            home: home, resolvedHome: CleanupScanner.resolvedPath(home) ?? home,
            hasFullDiskAccess: hasFullDiskAccess, exclusions: [], now: Date(),
            appName: { $0 == "com.raycast.macos" ? "Raycast" : nil })
    }

    static func buildHome() {
        write("Library/Caches/com.raycast.macos/data", bytes: 40_000)
        write("Library/Caches/com.raycast.macos/nested/more", bytes: 12_000)
        write("Library/Caches/com.example.Unknown/blob")
        write("Library/Caches/com.apple.akd/token")
        write("Library/Logs/app.log")
        write("Library/Logs/DiagnosticReports/App-2026.ips")
        write(derivedData + "/Build/out", bytes: 30_000)
        for version in ["16.0 (20A1)", "17.0 (21A2)", "18.0 (22A3)"] {
            write("Library/Developer/Xcode/iOS DeviceSupport/\(version)/Symbols/lib")
        }
        write("Library/Saved Application State/com.old.App.savedState/windows.plist")
        write("Library/Saved Application State/com.new.App.savedState/windows.plist")
        let old = Date(timeIntervalSinceNow: -90 * 86_400)
        try? FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: home + "/Library/Saved Application State/com.old.App.savedState")
        write("Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches/one")
        write("Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches/two")
        write("Library/Keychains/login.keychain-db")
        write("Documents/report.pages")
        write("outside/huge", bytes: 200_000, base: root)
        try? FileManager.default.createSymbolicLink(
            atPath: home + "/Library/Caches/com.raycast.macos/link", withDestinationPath: root + "/outside/huge")
        try? FileManager.default.linkItem(
            atPath: home + "/Library/Caches/com.raycast.macos/data",
            toPath: home + "/Library/Caches/com.raycast.macos/data-link")
    }

    // MARK: - Discovery

    static func testDiscovery() async {
        let items = await CleanupScanner.discover(environment())
        let byPath = Dictionary(items.map { (String($0.path.dropFirst(home.count + 1)), $0) }) { first, _ in first }
        expect(byPath["Library/Caches/com.raycast.macos"]?.match.target == .appCaches, "a recognized cache is found")
        expect(byPath["Library/Caches/com.raycast.macos"]?.name == "Raycast", "a cache is titled by its app")
        expect(
            byPath["Library/Caches/com.example.Unknown"]?.match.target == .otherAppCaches,
            "an unknown cache is listed for review")
        expect(byPath["Library/Caches/com.apple.akd"] == nil, "a protected cache is never found")
        expect(byPath["Library/Keychains/login.keychain-db"] == nil, "keychains are never found")
        expect(!items.contains { $0.path.contains("/Documents/") }, "documents are never found")
        expect(byPath["Library/Logs/app.log"]?.match.target == .logs, "an app log is found")
        expect(byPath["Library/Logs/DiagnosticReports"] == nil, "Logs leaves crash reports to their target")
        expect(
            byPath["Library/Logs/DiagnosticReports/App-2026.ips"]?.match.target == .crashReports,
            "a crash report is found")
        expect(byPath[derivedData]?.name == "Proj", "a DerivedData folder is titled by its project")
        let support = items.filter { $0.match.target == .deviceSupport }.map { ($0.path as NSString).lastPathComponent }
        expect(support == ["16.0 (20A1)"], "the newest two device support versions are kept")
        let states = items.filter { $0.match.target == .savedState }.map(\.name)
        expect(states == ["com.old.App"], "only saved state untouched for 30 days is offered")
        let container = byPath["Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches"]
        expect(container?.match.pattern.contentsOnly == true, "a container's cache folder is emptied, not removed")
        expect(items.allSatisfy { $0.size == nil }, "discovery leaves every size pending")

        let guarded = await CleanupScanner.discover(environment(hasFullDiskAccess: false))
        expect(!guarded.contains { $0.path.contains("/Library/Containers/") }, "containers are not listed without access")
    }

    // MARK: - Sizing

    static func testSizing() throws {
        let cache = home + "/Library/Caches/com.raycast.macos"
        let expected = blocks(cache + "/data") + blocks(cache + "/nested/more") + blocks(cache + "/link")
        let measured = try DiskUsageScanner.measure(cache)
        expect(measured.bytes == expected, "allocated bytes, a hard link counted once: \(measured.bytes) vs \(expected)")
        expect(!measured.isPartial, "a fully readable tree is not partial")
        let link = try DiskUsageScanner.measure(cache + "/link")
        expect(link.bytes == blocks(cache + "/link"), "a symlink is sized as itself")
        expect((try? DiskUsageScanner.measure(home + "/missing")) == nil, "a missing path throws")

        let locked = home + "/Library/Caches/com.example.Unknown/locked"
        write("Library/Caches/com.example.Unknown/locked/secret")
        chmod(locked, 0)
        defer { chmod(locked, 0o755) }
        let partial = try DiskUsageScanner.measure(home + "/Library/Caches/com.example.Unknown")
        expect(partial.isPartial, "an unreadable folder makes the total a floor")
    }

    static func testCancellation() async {
        let tree = home
        let cancelled = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            return (try? DiskUsageScanner.measure(tree)) == nil
        }
        cancelled.cancel()
        let stopped = await cancelled.value
        expect(stopped, "a cancelled walk stops instead of finishing")
    }

    static func testBatchedMeasure() async {
        let paths = [home + "/Library/Caches/com.raycast.macos", home + "/Library/Logs/app.log", home + "/nope"]
        let landed = Mutex<[String: DiskUsageScanner.Measurement]>([:])
        await DiskUsageScanner.measure(paths) { batch in
            landed.withLock { for (path, size) in batch { $0[path] = size } }
        }
        let results = landed.withLock { $0 }
        expect(results.count == 2, "every readable path lands once and a missing one never does")
    }

    // MARK: - Running

    static func request(
        _ items: [CleanupItem], mode: CleanupDeletionMode = .tiered, runtime: CleanupRuntime = .idle
    ) -> CleanupRunner.Request {
        CleanupRunner.Request(items: items, mode: mode, runtime: runtime, environment: environment())
    }

    static func testRun() async {
        let items = await CleanupScanner.discover(environment())
        func pick(_ relative: String) -> CleanupItem? { items.first { $0.path == home + "/" + relative } }
        guard let raycast = pick("Library/Caches/com.raycast.macos"),
            let unknown = pick("Library/Caches/com.example.Unknown"),
            let container = pick("Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches"),
            let log = pick("Library/Logs/app.log")
        else { return expect(false, "fixtures were discovered") }

        let operations = RecordingOperations()
        let report = await CleanupRunner.run(request([raycast, unknown, container]), operations: operations)
        let removed = operations.removed.withLock { $0 }
        let trashed = operations.trashed.withLock { $0 }
        expect(removed.contains(raycast.path), "a safe cache is deleted directly")
        expect(trashed == [unknown.path], "a reviewed cache goes to the Trash")
        expect(!removed.contains(container.path), "an emptied folder itself stays")
        expect(
            Set(removed.filter { $0.hasPrefix(container.path + "/") })
                == [container.path + "/one", container.path + "/two"],
            "each child of an emptied folder is removed")
        expect(report.removedCount == 3 && !report.hasFailures, "the report counts every item")
        let touched = removed + trashed
        let allowed = [raycast.path, unknown.path, container.path + "/"]
        expect(touched.allSatisfy { path in allowed.contains { path == $0 || path.hasPrefix($0) } },
            "nothing outside the picked items is touched")

        let trashOnly = RecordingOperations()
        _ = await CleanupRunner.run(request([raycast], mode: .trashOnly), operations: trashOnly)
        expect(trashOnly.trashed.withLock { $0 } == [raycast.path], "trash-only mode never deletes")

        let busy = RecordingOperations()
        let blocked = await CleanupRunner.run(
            request([raycast], runtime: CleanupRuntime(runningBundleIDs: ["com.raycast.macos"])), operations: busy)
        expect(blocked.failures.first?.reason == .running("com.raycast.macos"), "a running owner is re-checked")
        expect(busy.removed.withLock { $0 }.isEmpty, "a running owner's cache is left alone")

        let logs = home + "/Library/Logs"
        let decoy = root + "/decoy/Logs"
        try? FileManager.default.createDirectory(atPath: decoy, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(atPath: logs + "/app.log", toPath: decoy + "/app.log")
        try? FileManager.default.moveItem(atPath: logs, toPath: root + "/logs-original")
        try? FileManager.default.createSymbolicLink(atPath: logs, withDestinationPath: decoy)
        let swapped = RecordingOperations()
        let refused = await CleanupRunner.run(request([log]), operations: swapped)
        expect(refused.failures.first?.reason == .refused(.symlinkedAncestor), "a swapped-in symlink is refused")
        expect(swapped.removed.withLock { $0 }.isEmpty, "nothing behind the symlink is touched")

        try? FileManager.default.removeItem(atPath: unknown.path)
        let gone = await CleanupRunner.run(request([unknown]), operations: CleanupSystemFileOperations())
        expect(!gone.hasFailures, "an item already gone is done, not failed")
    }

    static func testFailureMapping() {
        expect(CleanupRunner.failure(from: CocoaError(.fileWriteNoPermission)) == .permissionDenied, "no permission")
        expect(CleanupRunner.failure(from: CocoaError(.fileNoSuchFile)) == nil, "already gone")
        expect(CleanupRunner.failure(from: CocoaError(.fileWriteVolumeReadOnly)) == .readOnly, "read-only")
        expect(CleanupRunner.failure(from: NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))) == .inUse, "busy")
        expect(CleanupRunner.failure(from: CancellationError()) == .cancelled, "cancelled")

        let sealed = root + "/sealed"
        write("sealed/file", base: root)
        chmod(sealed, 0o555)
        defer { chmod(sealed, 0o755) }
        do {
            try CleanupSystemFileOperations().remove(sealed + "/file")
            expect(false, "removing from a read-only folder fails")
        } catch {
            expect(CleanupRunner.failure(from: error) == .permissionDenied, "a real EACCES maps to permission")
        }
    }

    static func testSettings() {
        let suite = "cleanup-walk-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return expect(false, "suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CleanupSettingsStore(defaults: defaults)
        expect(store.deletionMode == .tiered, "fresh defaults delete rebuildable items, as the pane shows")
        expect(store.exclusions.isEmpty, "fresh defaults exclude nothing")
        let home = NSHomeDirectory()
        store.exclude(home + "/Library/Caches/com.example.app/")
        store.exclude(home + "/Library/Caches/com.example.app")
        expect(store.exclusions == ["~/Library/Caches/com.example.app"], "an exclusion is stored once, abbreviated")
        expect(
            store.resolvedExclusions == [home + "/Library/Caches/com.example.app"],
            "the scanner compares against the expanded path")
        store.deletionMode = .trashOnly
        let reloaded = CleanupSettingsStore(defaults: defaults)
        expect(reloaded.deletionMode == .trashOnly, "the deletion mode persists")
        expect(reloaded.exclusions == store.exclusions, "exclusions persist")
        expect(
            CleanupSettingsStore.normalize(["relative/path", " ~/A ", "~/A/", "/tmp/../tmp/B"]) == ["~/A", "/tmp/B"],
            "a hand-edited list drops relative paths and duplicates")
    }

    /// Ages every regular file below `relative`, so the project reads as untouched.
    static func age(_ relative: String, days: Double) {
        let date = Date(timeIntervalSinceNow: -days * 86_400)
        let base = home + "/" + relative
        let paths = [base] + (FileManager.default.subpaths(atPath: base) ?? []).map { base + "/" + $0 }
        for path in paths {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
        }
    }

    static func testProjects() async {
        write("code/idle/package.json")
        write("code/idle/package-lock.json")
        write("code/idle/src/index.js")
        write("code/idle/node_modules/left-pad/index.js", bytes: 20_000)
        age("code/idle", days: 90)
        write("code/fresh/package.json")
        write("code/fresh/yarn.lock")
        write("code/fresh/node_modules/x/index.js")
        write("code/unpinned/Cargo.toml")
        write("code/unpinned/target/debug/app", bytes: 9_000)
        age("code/unpinned", days: 90)
        write("code/infra/main.tf")
        write("code/infra/.terraform/terraform.tfstate")
        age("code/infra", days: 90)
        write("Library/stuff/package.json")
        write("Library/stuff/node_modules/x/index.js")
        age("Library/stuff", days: 90)

        let items = await CleanupProjectScanner.discover(environment())
        let byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0.match.target) })
        expect(byPath[home + "/code/idle/node_modules"] == .projectArtifacts, "an idle pinned project is safe")
        expect(byPath[home + "/code/fresh/node_modules"] == nil, "a project edited today is not offered")
        expect(byPath[home + "/code/unpinned/target"] == .projectArtifactsReview, "no lockfile means review")
        expect(byPath[home + "/code/infra/.terraform"] == nil, "Terraform state is never offered")
        expect(!items.contains { $0.path.contains("/Library/") }, "the walk never enters Library")
        expect(
            items.first { $0.path.hasSuffix("idle/node_modules") }?.name == "idle · node_modules",
            "a project row is named for its project")

        guard let idle = items.first(where: { $0.path.hasSuffix("idle/node_modules") }) else { return }
        let fresh = await CleanupProjectScanner.evidence(for: idle, environment: environment(), now: Date())
        expect(fresh != nil, "the runner can re-read an item's evidence")
        let busy = CleanupRuntime(workingDirectories: [home + "/code/idle/src"])
        let request = CleanupRunner.Request(items: [idle], mode: .tiered, runtime: busy, environment: environment())
        let operations = RecordingOperations()
        let report = await CleanupRunner.run(request, operations: operations)
        expect(report.failures.first?.reason == .inUse, "a shell inside the project stops the run")
        expect(operations.removed.withLock { $0.isEmpty }, "nothing in a busy project is removed")

        write("code/idle/src/new.js")
        let edited = await CleanupRunner.run(
            CleanupRunner.Request(items: [idle], mode: .tiered, runtime: .idle, environment: environment()),
            operations: operations)
        expect(
            edited.failures.first?.reason == .refused(.evidenceMismatch),
            "a project edited after the scan is refused at run time")
    }

    static func testFiles() async {
        write("Downloads/Tool.dmg", bytes: 3_000)
        write("Downloads/movie.mp4.crdownload", bytes: 3_000)
        write("Downloads/fresh.zip.crdownload", bytes: 3_000)
        age("Downloads/movie.mp4.crdownload", days: 3)
        write("Documents/Report.mov", bytes: 12 << 20)
        write("Documents/Archive/Report copy.mov", bytes: 12 << 20)
        age("Documents/Report.mov", days: 10)
        write("Movies/Render.mov", bytes: 3 << 20)
        write("Movies/.hidden/Huge.mov", bytes: 3 << 20)
        write("Movies/Library.photoslibrary/Huge.mov", bytes: 3 << 20)
        write("Pictures/Huge.mov", bytes: 3 << 20)

        var environment = environment()
        environment.largeFileThreshold = 2 << 20
        let items = await CleanupFileScanner.discover(environment)
        let byName = Dictionary(items.map { (($0.path as NSString).lastPathComponent, $0) }) { first, _ in first }
        expect(byName["Tool.dmg"]?.match.target == .installers, "a disk image in Downloads is an installer")
        expect(byName["movie.mp4.crdownload"]?.match.target == .incompleteDownloads, "a stalled download is offered")
        expect(byName["fresh.zip.crdownload"] == nil, "a download from today may still be running")
        expect(byName["Report copy.mov"]?.match.target == .duplicates, "the later copy is the duplicate")
        expect(byName["Report.mov"] == nil, "the earliest copy is kept and never listed")
        expect(byName["Report copy.mov"]?.match.captures == [home + "/Documents/Report.mov"], "the row names its keeper")
        expect(byName["Render.mov"]?.match.target == .largeFiles, "a file over the threshold is large")
        expect(!items.contains { $0.path.contains("/.hidden/") }, "hidden folders are skipped")
        expect(!items.contains { $0.path.contains(".photoslibrary") }, "nothing inside a library is offered")
        expect(!items.contains { $0.path.contains("/Pictures/") }, "Pictures is never walked")
        for item in items {
            expect(item.target.tier == .review && item.target.disposition == .trash, "\(item.name) is reviewed and trashed")
        }

        guard let copy = byName["Report copy.mov"], let tool = byName["Tool.dmg"] else { return }
        write("Documents/Archive/Report copy.mov", bytes: 12 << 20 + 1)
        let operations = RecordingOperations()
        let report = await CleanupRunner.run(
            CleanupRunner.Request(items: [copy, tool], mode: .tiered, runtime: .idle, environment: environment),
            operations: operations)
        expect(
            report.failures.map(\.reason) == [.refused(.evidenceMismatch)],
            "a copy that changed after the scan is no longer a duplicate")
        expect(operations.trashed.withLock { $0 } == [home + "/Downloads/Tool.dmg"], "an installer goes to the Trash")
    }

    static func testLeftovers() async {
        write("Library/Application Support/com.gone.Editor/state.db")
        age("Library/Application Support/com.gone.Editor", days: 60)
        write("Library/Application Support/com.installed.App.helper/state.db")
        age("Library/Application Support/com.installed.App.helper", days: 60)
        write("Library/Application Support/com.recent.Tool/state.db")
        let agent = NSDictionary(dictionary: ["Label": "com.gone.agent", "ProgramArguments": [root + "/missing/bin"]])
        folder("Library/LaunchAgents")
        agent.write(toFile: home + "/Library/LaunchAgents/com.gone.agent.plist", atomically: true)
        write(".vscode/extensions/ms-python.python-1.0.0/package.json")
        write(".vscode/extensions/ms-python.python-2.0.0/package.json")
        FileManager.default.createFile(
            atPath: home + "/.vscode/extensions/.obsolete", contents: Data(#"{"ms-python.python-1.0.0":true}"#.utf8))
        for version in ["2.1.1", "2.1.2", "2.1.3"] { write(".local/share/claude/versions/\(version)", bytes: 1_000) }
        folder(".local/bin")
        try? FileManager.default.createSymbolicLink(
            atPath: home + "/.local/bin/claude", withDestinationPath: home + "/.local/share/claude/versions/2.1.2")

        var environment = environment()
        environment.knownBundleIDs = ["com.installed.app"]
        let items = CleanupLeftoverScanner.discover(environment)
        let paths = Set(items.map(\.path))
        expect(paths.contains(home + "/Library/Application Support/com.gone.Editor"), "a removed app's data is offered")
        expect(!paths.contains { $0.contains("com.installed.App.helper") }, "an installed app's helper keeps its data")
        expect(!paths.contains { $0.contains("com.recent.Tool") }, "data written today is kept")
        expect(paths.contains(home + "/Library/LaunchAgents/com.gone.agent.plist"), "a dead launch agent is offered")
        expect(paths.contains(home + "/.vscode/extensions/ms-python.python-1.0.0"), "an obsolete extension is offered")
        expect(!paths.contains(home + "/.vscode/extensions/ms-python.python-2.0.0"), "the installed one is not")
        expect(paths.contains(home + "/.local/share/claude/versions/2.1.1"), "an old CLI version is offered")
        expect(!paths.contains(home + "/.local/share/claude/versions/2.1.2"), "the linked version is kept")
        expect(!paths.contains(home + "/.local/share/claude/versions/2.1.3"), "the newest version is kept")
    }

    static func testPhotoLibrarySkipped() throws {
        write("Pictures/Photos Library.photoslibrary/originals/a.heic", bytes: 50_000)
        write("Pictures/other.png", bytes: 5_000)
        let skipping = CleanupScanner.guardedFolders(home: home)
        let measured = try DiskUsageScanner.measure(home + "/Pictures", skipping: skipping)
        expect(measured.isPartial, "a photo library is stepped around without Full Disk Access")
        expect(measured.bytes < 50_000, "and none of its bytes are read")
        expect(CleanupScanner.isGuarded(home + "/Pictures/Photos Library.photoslibrary/", home: home), "it is guarded")
    }

    static func main() async {
        buildHome()
        await testDiscovery()
        do { try testSizing() } catch { expect(false, "sizing threw \(error)") }
        await testCancellation()
        await testBatchedMeasure()
        await testRun()
        testFailureMapping()
        testSettings()
        do { try testPhotoLibrarySkipped() } catch { expect(false, "photo library walk threw \(error)") }
        await testProjects()
        await testFiles()
        await testLeftovers()
        try? FileManager.default.removeItem(atPath: root)
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
