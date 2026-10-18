import Darwin
import Foundation

@main
@MainActor
struct CleanupTests {
    static var failures = 0
    static var passes = 0

    static let home = "/Users/tester"

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    // MARK: - Fixtures

    static func context(for path: String, resolvedParent: String? = nil) -> CleanupPathContext {
        CleanupPathContext(
            home: home, resolvedHome: home,
            resolvedParent: resolvedParent ?? (path as NSString).deletingLastPathComponent)
    }

    static func verdict(_ relative: String) -> CleanupVerdict {
        let path = home + "/" + relative
        return CleanupSafetyPolicy.evaluate(path: path, context: context(for: path))
    }

    static func refusal(_ relative: String) -> CleanupRefusal? {
        if case .refused(let refusal) = verdict(relative) { return refusal }
        return nil
    }

    static func target(_ relative: String) -> CleanupTargetID? {
        if case .allowed(let match) = verdict(relative) { return match.target }
        return nil
    }

    static func item(
        _ relative: String, size: Int64? = 100, protection: UninstallProtection = .removable
    ) -> CleanupItem {
        let components = relative.split(separator: "/").map(String.init)
        guard let match = CleanupCatalog.resolve(components) else {
            fatalError("fixture is not in the catalog: \(relative)")
        }
        return CleanupItem(
            path: home + "/" + relative, match: match, name: components.last ?? relative, size: size,
            modified: nil, protection: protection)
    }

    // MARK: - Never delete

    static func testNeverDeleteRoots() {
        let roots = [
            "Library/Keychains", "Library/Preferences", "Library/Mail", "Library/Accounts",
            "Library/Messages", "Library/Cookies", "Library/Safari", "Library/Mobile Documents",
            "Library/CloudStorage", "Library/Group Containers", "Library/Application Support/JetBrains",
            "Library/Application Support/MobileSync", "Documents", "Desktop", "Downloads", "Pictures",
            "Music", "Movies", ".ssh", ".gnupg"
        ]
        for root in roots {
            expect(refusal(root) == .neverDelete, "\(root) itself is never offered")
            expect(refusal(root + "/inner") == .neverDelete, "nothing under \(root) is offered")
        }
        expect(refusal("Library/Messages/chat.db") == .neverDelete, "the Messages database is refused")
        expect(
            target("Library/Messages/Caches/Previews/item") == .messagesPreviews,
            "the audited Messages previews exception is allowed")
    }

    static func testOutsideHome() {
        let context = CleanupPathContext(home: home, resolvedHome: home, resolvedParent: "/")
        for path in ["/Users/tester", "/Library/Caches/x", "/System/Library/Caches/x", "/Applications/X.app",
            "/private/var/folders/ab/x", "/Users/other/Library/Caches/x"]
        {
            expect(
                CleanupSafetyPolicy.evaluate(path: path, context: context) == .refused(.outsideHome),
                "\(path) is outside the home directory")
        }
    }

    static func testPathSpellings() {
        expect(refusal("LIBRARY/KEYCHAINS/login.keychain-db") == .neverDelete, "deny rules ignore case")
        expect(refusal("library/preferences/x.plist") == .neverDelete, "lowercase spelling is denied too")
        expect(refusal("Library/Caches/../Keychains/x") == .notStandardized, "dot-dot is refused")
        expect(refusal("Library/Caches/./x") == .notStandardized, "a dot component is refused")
        expect(refusal("Library//Caches/x") == .notStandardized, "an empty component is refused")
        expect(refusal("Library/Caches/com.raycast.macos/") == .notStandardized, "a trailing slash is refused")
        expect(
            CleanupSafetyPolicy.evaluate(path: "Library/Caches/x", context: context(for: "x"))
                == .refused(.notStandardized),
            "a relative path is refused")
    }

    static func testSymlinkedAncestors() {
        let path = home + "/Library/Caches/com.raycast.macos"
        expect(
            CleanupSafetyPolicy.evaluate(
                path: path, context: context(for: path, resolvedParent: home + "/Documents"))
                == .refused(.symlinkedAncestor),
            "a parent that resolves elsewhere is refused")
        expect(
            CleanupSafetyPolicy.evaluate(
                path: path,
                context: CleanupPathContext(home: home, resolvedHome: home, resolvedParent: nil))
                == .refused(.symlinkedAncestor),
            "an unresolvable parent is refused")
        let relocated = CleanupPathContext(
            home: home, resolvedHome: "/Volumes/Data/tester",
            resolvedParent: "/Volumes/Data/tester/Library/Caches")
        expect(
            CleanupSafetyPolicy.evaluate(path: path, context: relocated) == .allowed(
                CleanupCatalog.resolve(["Library", "Caches", "com.raycast.macos"])!),
            "a home that itself lives elsewhere is followed consistently")
    }

    // MARK: - Protected names

    static func testProtectedNames() {
        let names = [
            "com.apple.akd", "CloudKit", "COM.APPLE.AKD", "FamilyCircle", "com.1password.1password",
            "com.apple.Spotlight", "com.apple.FontRegistry", "com.apple.dock.extra",
            "com.crowdstrike.falcon", "com.apple.inputmethod.Kotoeri", "com.apple.ScreenTimeAgent",
            "com.apple.containermanagerd", "com.apple.iCloudHelper", "com.apple.homed",
            "com.apple.ap.adprivacyd", "com.apple.LaunchServices", "com.apple.iconservices.store",
            "com.bitwarden.desktop", "com.apple.systemsettings.menucache", "com.apple.amsaccountsd"
        ]
        for name in names {
            expect(refusal("Library/Caches/\(name)") == .protectedName, "\(name) is never offered")
        }
        expect(
            refusal("Library/Containers/com.apple.Safari/Data/Library/Caches") == .protectedName,
            "the Safari container is guarded by macOS")
        expect(
            refusal("Library/Containers/com.agilebits.onepassword7/Data/Library/Caches") == .protectedName,
            "password manager containers are never offered")
        expect(target("Library/Caches/com.apple.Safari") == .safari, "Safari's own cache is offered")
        expect(
            refusal("Library/Logs/DiagnosticReportsForNewHardware") == .protectedName,
            "the system's new-hardware reports are never offered")
    }

    static func testOwnApp() {
        for path in [
            "Library/Caches/com.tinycast.app", "Library/Caches/com.tinycast.app.dev",
            "Library/Containers/com.tinycast.app.dev/Data/Library/Caches",
            "Library/Application Support/com.tinycast.app/Cache"
        ] {
            expect(refusal(path) == .ownApp, "\(path) belongs to Tinycast")
        }
    }

    // MARK: - Incidents

    /// Purge 2026-09-11: an IDE's plugins and settings were treated as a cache.
    static func testJetBrains() {
        expect(
            refusal("Library/Application Support/JetBrains/IntelliJIdea2025.1/plugins") == .neverDelete,
            "JetBrains settings are refused before any allow rule")
        expect(
            refusal("Library/Caches/JetBrains/IntelliJIdea2025.1/LocalHistory") == .neverDelete,
            "local history is refused")
        expect(
            target("Library/Caches/JetBrains/IntelliJIdea2025.1/caches") == .editorCaches,
            "an IDE's caches are offered")
        expect(
            refusal("Library/Caches/JetBrains") == .notInCatalog, "the JetBrains root is never one row")
        expect(
            refusal("Library/Caches/JetBrains/IntelliJIdea2025.1") == .notInCatalog,
            "a whole IDE folder is never one row")
    }

    /// Purge 2026-10-06: an audit that found settings and installed tools tagged Safe.
    static func testAuditNarrowings() {
        expect(refusal(".gem/ruby/3.3.0/gems") == .notInCatalog, "installed gems are refused")
        expect(target(".gem/ruby/3.3.0/cache") == .packageCaches, "the gem download cache is offered")
        expect(refusal(".android/avd") == .notInCatalog, "Android emulators are refused")
        expect(refusal(".android/debug.keystore") == .notInCatalog, "the debug keystore is refused")
        expect(target(".android/cache") == .packageCaches, "Android's cache is offered")
        expect(refusal(".sbt") == .notInCatalog, "sbt settings are refused")
        expect(refusal("Library/Application Support/Zed/db") == .notInCatalog, "Zed's database is refused")
        expect(
            refusal("Library/Application Support/Code/User/workspaceStorage/abc") == .neverDelete,
            "editor workspace storage holds AI chat history")
        expect(
            refusal("Library/Caches/pypoetry/virtualenvs") == .neverDelete,
            "Poetry environments are refused")
        expect(refusal("Library/Caches/pypoetry") == .notInCatalog, "Poetry's root is never one row")
        expect(target("Library/Caches/pypoetry/cache") == .packageCaches, "Poetry's cache is offered")
        expect(refusal(".expo/state.json") == .notInCatalog, "Expo's login is refused")
        expect(target(".expo/template-cache") == .packageCaches, "Expo's caches are offered")
    }

    /// Purge 2026-07-12, 07-25, 10-01: user data, sync state and Docker tagged Safe.
    static func testNeverSafe() {
        let spotify = target("Library/Caches/com.spotify.client")
        expect(spotify == .otherAppCaches, "Spotify can hold offline songs, so it is reviewed")
        expect(target("Library/Caches/com.apple.appstoreagent") == .otherAppCaches, "App Store state is reviewed")
        expect(target("Library/Caches/com.apple.e5rt.e5bundlecache") == .otherAppCaches, "E5RT is reviewed")
        expect(target("Library/Caches/com.apple.bird") == .otherAppCaches, "iCloud Drive state is reviewed")
        expect(refusal("Library/Caches/com.docker.docker") == .notInCatalog, "Docker is cleaned by command")
        expect(
            refusal("Library/Containers/com.docker.docker/Data/Library/Caches") == .notInCatalog,
            "Docker's container is never trashed")
        expect(refusal("Library/Caches/Homebrew") == .notInCatalog, "Homebrew is cleaned by command")
        expect(refusal("Library/Caches/go-build") == .notInCatalog, "Go is cleaned by command")
        expect(
            refusal("Library/Developer/CoreSimulator/Devices/ABC") == .notInCatalog,
            "simulators are removed by simctl")
    }

    static func testCacheClassification() {
        let unknown = item("Library/Caches/com.example.Unknown")
        expect(unknown.match.target == .otherAppCaches, "an unknown cache is listed for review")
        expect(unknown.target.tier == .review && unknown.target.disposition == .trash, "unknown goes to the Trash")
        expect(target("Library/Caches/com.tinyspeck.slackmacgap") == .appCaches, "Slack's cache is recognized")
        expect(
            target("Library/Caches/com.anthropic.claudefordesktop.ShipIt") == .appCaches,
            "a Squirrel update cache is recognized by its suffix")
        expect(
            target("Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches") == .appCaches,
            "a container's cache folder is classified by its container")
        let child = CleanupCatalog.resolve(
            "Library/Containers/com.example.App/Data/Library/Caches/blob".split(separator: "/").map(String.init))
        expect(child?.isContentsChild == true && child?.target == .otherAppCaches, "a contents child resolves")
        expect(
            refusal("Library/Containers/com.example.App/Data/Library/Caches/blob/deeper") == .notInCatalog,
            "only direct children of an emptied folder are removable")
        expect(refusal("Library/Containers/com.example.App/Data/Documents") == .notInCatalog, "app data is refused")
        for name in CleanupCatalog.recognizedCaches {
            expect(!CleanupSafetyPolicy.isProtectedName(name), "\(name) is recognized yet protected")
            expect(
                CleanupCatalog.resolve(["Library", "Caches", name])?.target == .appCaches,
                "\(name) is recognized but claimed elsewhere")
        }
    }

    // MARK: - Catalog

    static func testCatalogAudit() {
        let ids = CleanupCatalog.targets.map(\.id)
        expect(Set(ids).count == ids.count, "each target appears once")
        expect(Set(ids) == Set(CleanupTargetID.allCases), "every target ID is in the catalog")
        for target in CleanupCatalog.targets where target.isSelectable && target.source == .catalog {
            let expected: CleanupDisposition = target.tier == .safe ? .delete : .trash
            expect(target.disposition == expected, "\(target.id) disposition matches its tier")
        }
        let specific = CleanupCatalog.targets.filter { !$0.isGeneric }
        for reserved in CleanupCatalog.reservedPatterns {
            for target in specific {
                let overlaps = target.patterns.contains {
                    $0.covers(reserved.components) || reserved.covers($0.components)
                }
                expect(!overlaps, "\(target.id) overlaps the reserved \(reserved.components)")
            }
        }
        for target in specific {
            for pattern in target.patterns {
                let sample = pattern.components.map { $0 == "*" ? "Sample-1" : $0 }
                expect(
                    CleanupCatalog.resolve(sample)?.target == target.id,
                    "\(sample.joined(separator: "/")) round-trips to \(target.id)")
            }
        }
        expect(target("Library/Logs/com.example.log") == .logs, "an app log is offered")
        expect(refusal("Library/Logs/DiagnosticReports") == .notInCatalog, "Logs never swallows crash reports")
        expect(target("Library/Logs/DiagnosticReports/App.ips") == .crashReports, "crash reports are per file")
        expect(target(".Trash") == .trash, "the Trash has a row")
        for target in CleanupCatalog.targets where target.source != .catalog {
            expect(target.patterns.isEmpty, "\(target.id) is proposed, never expanded from patterns")
        }
        expect(!CleanupCatalog.target(.trash).isSelectable, "the Trash is emptied by its own action")
    }

    static func testBrowsers() {
        let base = "Library/Application Support/Google/Chrome"
        expect(target("\(base)/Default/Code Cache") == .chrome, "a profile's code cache is Chrome's")
        expect(target("\(base)/Profile 2/GPUCache") == .chrome, "any profile is covered")
        expect(target("\(base)/GrShaderCache") == .chrome, "the root shader cache is Chrome's")
        expect(target("\(base)/Default/Service Worker/CacheStorage") == .serviceWorkers, "workers are reviewed")
        expect(refusal("\(base)/Default/Cookies") == .notInCatalog, "cookies are refused")
        expect(refusal("\(base)/Default/History") == .notInCatalog, "history is refused")
        expect(target("Library/Caches/Google/Chrome") == .chrome, "Chrome's HTTP cache is Chrome's")
        expect(refusal("Library/Caches/Google") == .notInCatalog, "Google's root is never a generic row")
        expect(target("\(base)/Crashpad/completed/report.dmp") == .chrome, "completed crash dumps are offered")
        expect(refusal("\(base)/Crashpad/pending") == .notInCatalog, "pending crash dumps are refused")
    }

    // MARK: - Running owners

    static func testRunningOwners() {
        func owner(_ relative: String, apps: Set<String> = [], tools: Set<String> = []) -> String? {
            CleanupSafetyPolicy.runningOwner(
                of: item(relative).match,
                runtime: CleanupRuntime(runningBundleIDs: apps, runningProcesses: tools))
        }
        expect(
            owner("Library/Caches/com.tinyspeck.slackmacgap", apps: ["com.tinyspeck.slackmacgap"]) != nil,
            "a running app locks its own cache")
        expect(
            owner("Library/Caches/com.anthropic.claudefordesktop.ShipIt", apps: ["com.anthropic.claudefordesktop"])
                != nil,
            "an app locks its namespaced helper caches")
        expect(
            owner("Library/Caches/Google/Chrome", apps: ["com.google.Chrome.framework.AlertNotificationService"])
                == "com.google.Chrome",
            "a running helper names the app it belongs to")
        expect(owner("Library/Caches/com.tinyspeck.slackmacgap", apps: ["com.tinyspeck.slack"]) == nil,
            "a prefix without a dot boundary is someone else")
        expect(owner("Library/Developer/Xcode/DerivedData/App-x", apps: ["com.apple.dt.Xcode"]) != nil,
            "Xcode locks DerivedData")
        expect(owner("Library/Developer/Xcode/DerivedData/App-x", tools: ["xcodebuild"]) != nil,
            "a command-line build locks DerivedData")
        expect(owner("Library/Caches/JetBrains/IntelliJIdea2025.1/caches", apps: ["com.jetbrains.intellij.ce"])
            != nil, "a JetBrains IDE locks the JetBrains caches")
        expect(owner(".cargo/registry", tools: ["cargo"]) != nil, "a running cargo locks its registry")
        expect(owner(".cargo/registry") == nil, "nothing running, nothing locked")
        expect(owner("Library/Caches/com.apple.parsecd", apps: ["com.apple.Safari"]) == nil,
            "an unrelated app locks nothing")
    }

    // MARK: - Plan and selection

    static func makePlan(generation: Int = 1) -> (CleanupPlan, [CleanupItem]) {
        var plan = CleanupPlan(generation: generation)
        let items = [
            item("Library/Caches/com.raycast.macos"),
            item("Library/Caches/com.example.Unknown"),
            item("Library/Caches/com.tinyspeck.slackmacgap"),
            item("Library/Caches/com.linear", protection: .userLocked),
            item("Library/Developer/Xcode/DerivedData/App-x", size: nil)
        ]
        plan.add(items)
        return (plan, items)
    }

    static func testSelection() {
        let (plan, items) = makePlan()
        let runtime = CleanupRuntime(runningBundleIDs: ["com.tinyspeck.slackmacgap"])
        var selection = CleanupSelection()
        selection.preselect(items)
        let effective = selection.effective(in: plan, runtime: runtime, exclusions: []).map(\.path)
        expect(effective.contains(items[0].path), "a safe free row is checked")
        expect(!effective.contains(items[1].path), "a reviewed row is never preselected")
        expect(!effective.contains(items[2].path), "a running app's row drops out while it runs")
        expect(!effective.contains(items[3].path), "a locked row never counts")
        expect(effective.contains(items[4].path), "a pending size is still cleanable")
        expect(
            selection.effective(in: plan, runtime: .idle, exclusions: []).contains(items[2]),
            "the row comes back once the app quits")

        selection.toggle(items[1], in: plan, runtime: runtime, exclusions: [])
        expect(selection.isChecked(items[1], in: plan, runtime: runtime, exclusions: []), "a review row can be picked")
        selection.toggle(items[3], in: plan, runtime: runtime, exclusions: [])
        expect(!selection.isChecked(items[3], in: plan, runtime: runtime, exclusions: []), "a locked row can't")

        let excluded = selection.effective(
            in: plan, runtime: runtime, exclusions: [home + "/Library/Caches/com.raycast.macos"])
        expect(!excluded.contains(items[0]), "an exclusion subtracts a checked row")
        let raycast = home + "/Library/Caches/com.raycast.macos"
        expect(CleanupExclusions.contains(raycast + "/x", in: [raycast]), "an exclusion covers what is inside it")
        expect(
            !CleanupExclusions.contains(raycast, in: [home + "/Library/Caches/com.raycast"]),
            "an exclusion stops at a component boundary")
    }

    static func testGroupToggle() {
        let (plan, items) = makePlan()
        guard let group = plan.group(.appCaches) else { return expect(false, "app caches group exists") }
        var selection = CleanupSelection()
        expect(selection.state(of: group, in: plan, runtime: .idle, exclusions: []) == .off, "nothing checked")
        selection.toggle(items[0], in: plan, runtime: .idle, exclusions: [])
        expect(selection.state(of: group, in: plan, runtime: .idle, exclusions: []) == .mixed, "one of two")
        selection.toggle(group, in: plan, runtime: .idle, exclusions: [])
        expect(selection.state(of: group, in: plan, runtime: .idle, exclusions: []) == .on, "the rest join")
        expect(
            !selection.isChecked(items[3], in: plan, runtime: .idle, exclusions: []),
            "a group toggle skips a locked row")
        selection.toggle(group, in: plan, runtime: .idle, exclusions: [])
        expect(selection.state(of: group, in: plan, runtime: .idle, exclusions: []) == .off, "all leave together")
    }

    static func testStreamedSizes() {
        var (plan, items) = makePlan(generation: 2)
        let order = plan.items.map(\.path)
        plan.setSize(9_000, isPartial: true, forPath: items[4].path, generation: 2)
        expect(plan.item(items[4].path)?.size == 9_000, "a current size lands")
        expect(plan.item(items[4].path)?.isPartial == true, "a partial walk is marked")
        plan.setSize(1, isPartial: false, forPath: items[4].path, generation: 1)
        expect(plan.item(items[4].path)?.size == 9_000, "a stale scan's size is ignored")
        expect(plan.items.map(\.path) == order, "a landed size never reorders")
        plan.add([items[0]])
        expect(plan.items.count == items.count, "a path already listed is not added twice")
        plan.remove([items[0].path])
        expect(plan.item(items[0].path) == nil, "a cleaned path leaves the plan")
        plan.setSize(7, isPartial: false, forPath: items[4].path, generation: 2)
        expect(plan.item(items[4].path)?.size == 7, "the index survives a removal")
        expect(plan.item(items[1].path)?.size == 100, "a neighbour keeps its size")
    }

    static func testAutomaticItems() {
        let (plan, items) = makePlan()
        let runtime = CleanupRuntime(runningBundleIDs: ["com.tinyspeck.slackmacgap"])
        let automatic = plan.automaticItems(runtime: runtime, exclusions: [items[4].path])
        expect(automatic == [items[0]], "only audited, safe, delete-type, free and unexcluded rows run unattended")
    }

    // MARK: - Policies

    static func testKeepNewest() {
        let names = [
            "16.4 (20E247)", "17.0 (21A329) arm64e", "17.5.1 (21F90) arm64e", "iPhone15,2 17.2 (21C62)",
            "weird"
        ]
        expect(
            KeepNewestPolicy.removable(names, keep: 2) == ["16.4 (20E247)", "17.0 (21A329) arm64e"],
            "the two newest versions and anything unreadable stay")
        expect(KeepNewestPolicy.removable(["17.0 (A)", "17.0 (B)"], keep: 1) == ["17.0 (A)"], "ties keep one")
        expect(KeepNewestPolicy.version(in: "iPhone15,2 17.0.1 (21A340)") == [17, 0, 1], "model prefixes skip")
        expect(KeepNewestPolicy.removable(["17.0"], keep: 2).isEmpty, "fewer than keep removes nothing")
    }

    static func testDeletionMode() {
        expect(CleanupDeletionMode.tiered.resolve(.delete) == .delete, "tiered deletes")
        expect(CleanupDeletionMode.trashOnly.resolve(.delete) == .trash, "trash-only never deletes")
        expect(CleanupDeletionMode.trashOnly.resolve(.trash) == .trash, "trash stays trash")
    }

    static func testReport() {
        expect(CleanupFailure.from(errno: ENOENT) == nil, "already gone is done")
        expect(CleanupFailure.from(errno: EACCES) == .permissionDenied, "EACCES")
        expect(CleanupFailure.from(errno: EPERM) == .permissionDenied, "EPERM")
        expect(CleanupFailure.from(errno: EBUSY) == .inUse, "EBUSY")
        expect(CleanupFailure.from(errno: EROFS) == .readOnly, "EROFS")
        expect(CleanupFailure.from(errno: ENOSPC) == .other(ENOSPC), "anything else keeps its code")

        var report = CleanupReport()
        report.recordDeleted(bytes: 1 << 30)
        report.recordTrashed(bytes: 100)
        report.recordFailure(name: "x", path: "/x", reason: .inUse)
        expect(report.removedBytes == (1 << 30) + 100 && report.removedCount == 2, "tallies add up")
        expect(report.hasFailures, "a failure is kept")
        expect(!report.isHeldBySnapshots, "no reading, no snapshot note")
        report.volumeGain = 10 << 20
        expect(report.isHeldBySnapshots, "a gigabyte deleted for 10 MB freed points at snapshots")
        report.volumeGain = 900 << 20
        expect(!report.isHeldBySnapshots, "most of it came back")
    }

    static func testNaming() {
        expect(
            CleanupNaming.derivedDataProject("Tinycast-dpgxwzfhpqxvdebcmkadnfgztsyr") == "Tinycast",
            "the hash suffix is dropped")
        expect(CleanupNaming.derivedDataProject("ModuleCache.noindex") == "ModuleCache.noindex", "no hash, no change")
        expect(CleanupNaming.derivedDataProject("My-App-short") == "My-App-short", "a short suffix is part of the name")
        expect(CleanupNaming.strippingKnownExtension("com.apple.Safari.savedState") == "com.apple.Safari", "state")
        expect(CleanupNaming.strippingKnownExtension(".ipsw") == ".ipsw", "an extension alone is a name")

        func title(_ relative: String, apps: [String: String] = [:]) -> String {
            let components = relative.split(separator: "/").map(String.init)
            guard let match = CleanupCatalog.resolve(components) else { return "<unresolved>" }
            return CleanupNaming.title(for: match, leaf: components.last ?? "", appName: { apps[$0] })
        }
        let chrome = "Library/Application Support/Google/Chrome"
        expect(title("\(chrome)/Default/Code Cache") == "Default · Code Cache", "a profile cache names its profile")
        expect(title("\(chrome)/Crashpad/completed") == "Crashpad", "a unique label stands alone")
        expect(title("\(chrome)/GrShaderCache") == "Chrome · GrShaderCache", "a shared label keeps the folder")
        expect(title(".npm/_npx") == "npx", "a package cache is its tool")
        expect(title(".cargo/git") == "Cargo · git", "two folders of one tool stay apart")
        expect(title("Library/Caches/JetBrains/IntelliJIdea2025.1/caches") == "IntelliJIdea2025.1 · caches", "IDE")
        expect(
            title("\(chrome)/Default/Service Worker/CacheStorage") == "Chrome · Default · CacheStorage",
            "a multi-browser group names the browser")
        expect(
            title("Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)") == "iOS · 17.0 (21A329)",
            "device support names its platform")
        expect(
            title("Library/Caches/com.raycast.macos", apps: ["com.raycast.macos": "Raycast"]) == "Raycast",
            "a cache takes its app's name")
        expect(title("Library/Caches/com.example.Gone") == "com.example.Gone", "an uninstalled app keeps its ID")
        expect(
            title("Library/Saved Application State/com.apple.Safari.savedState", apps: ["com.apple.Safari": "Safari"])
                == "Safari",
            "saved state takes its app's name")
    }

    // MARK: - Projects

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func evidence(
        root: String = home + "/code/app", folder: String = "node_modules", lockfile: Bool = true,
        holdsState: Bool = false, tracked: Bool? = false, idleFor days: Double? = 60, truncated: Bool = false,
        gitLocked: Bool = false, markers: Bool = true
    ) -> CleanupProjectEvidence {
        guard let rule = CleanupProjectRules.rules.first(where: { $0.folder == folder }) else {
            fatalError("no rule for \(folder)")
        }
        return CleanupProjectEvidence(
            root: root, rule: rule, hasRootMarker: markers, hasLockfile: lockfile, holdsState: holdsState,
            isTracked: tracked, lastActivity: days.map { now.addingTimeInterval(-$0 * 86_400) },
            activityTruncated: truncated, isGitLocked: gitLocked, idleDays: 30, now: now)
    }

    static func projectVerdict(_ evidence: CleanupProjectEvidence, expected: CleanupTargetID) -> CleanupVerdict {
        let path = CleanupProjectPolicy.artifactPath(evidence)
        var context = context(for: path)
        context.evidence = .project(evidence)
        return CleanupSafetyPolicy.evaluate(path: path, expected: expected, context: context)
    }

    static func testProjectPolicy() {
        expect(CleanupProjectPolicy.decide(evidence()) == .offered(.projectArtifacts), "idle, pinned and audited is safe")
        expect(
            CleanupProjectPolicy.decide(evidence(lockfile: false)) == .offered(.projectArtifactsReview),
            "no lockfile means a reinstall may differ, so review")
        expect(
            CleanupProjectPolicy.decide(evidence(folder: "Library")) == .offered(.projectArtifactsReview),
            "Unity's Library is never safe")
        expect(
            CleanupProjectPolicy.decide(evidence(idleFor: 3)) == .hidden(.recentlyUsed), "a project in use is hidden")
        expect(
            CleanupProjectPolicy.decide(evidence(idleFor: 3, truncated: true)) == .offered(.projectArtifactsReview),
            "an unproven project is offered only for review")
        expect(CleanupProjectPolicy.decide(evidence(idleFor: nil)) == .offered(.projectArtifactsReview), "unknown activity")
        expect(CleanupProjectPolicy.decide(evidence(tracked: true)) == .hidden(.tracked), "tracked files are never offered")
        expect(
            CleanupProjectPolicy.decide(evidence(tracked: nil)) == .hidden(.trackingUnknown),
            "a repository git could not answer for is hidden")
        expect(
            CleanupProjectPolicy.decide(evidence(folder: ".terraform", holdsState: true)) == .hidden(.holdsState),
            "Terraform state is refused outright")
        expect(CleanupProjectPolicy.decide(evidence(gitLocked: true)) == .hidden(.gitBusy), "git busy hides the project")
        expect(CleanupProjectPolicy.decide(evidence(markers: false)) == .hidden(.notThisProject), "no marker, no project")
        expect(
            CleanupProjectPolicy.isInUse(
                root: home + "/code/app", workingDirectories: [home + "/code/app/src"]),
            "a shell inside the project marks it in use")
        expect(
            !CleanupProjectPolicy.isInUse(root: home + "/code/app", workingDirectories: [home + "/code/application"]),
            "a sibling with a longer name is not inside")

        if case .allowed(let match) = projectVerdict(evidence(), expected: .projectArtifacts) {
            expect(match.captures == [home + "/code/app"], "the match remembers its project root")
        } else {
            expect(false, "an idle node_modules passes the gate")
        }
        let documents = evidence(root: home + "/Documents/app")
        expect(
            projectVerdict(documents, expected: .projectArtifacts) != .refused(.neverDelete),
            "a project in Documents can offer its own artifact")
        expect(
            projectVerdict(evidence(root: home + "/Library/app"), expected: .projectArtifacts)
                == .refused(.neverDelete) || projectVerdict(evidence(root: home + "/Library/app"), expected: .projectArtifacts)
                == .refused(.evidenceMismatch),
            "nothing under Library is a project")
        expect(
            projectVerdict(evidence(root: home + "/Pictures/app"), expected: .projectArtifacts) == .refused(.neverDelete),
            "Pictures stays never-delete even for projects")
        expect(
            projectVerdict(evidence(lockfile: false), expected: .projectArtifacts) == .refused(.evidenceMismatch),
            "the gate re-decides the tier rather than trusting the caller")
        expect(
            projectVerdict(evidence(tracked: true), expected: .projectArtifactsReview) == .refused(.evidenceMismatch),
            "tracked evidence refuses at the gate")
        let path = home + "/code/app/src"
        var context = context(for: path)
        context.evidence = .project(evidence())
        expect(
            CleanupSafetyPolicy.evaluate(path: path, expected: .projectArtifacts, context: context)
                == .refused(.evidenceMismatch),
            "evidence for one folder never vouches for another")
        expect(
            CleanupSafetyPolicy.evaluate(
                path: CleanupProjectPolicy.artifactPath(evidence()), expected: .projectArtifacts,
                context: self.context(for: CleanupProjectPolicy.artifactPath(evidence())))
                == .refused(.evidenceMismatch),
            "a project folder without evidence is refused")
        expect(refusal("code/app/node_modules") == .notInCatalog, "a catalog lookup never offers a project folder")
        let folders = CleanupProjectRules.rules.map(\.folder)
        expect(Set(CleanupProjectRules.rules).count == folders.count, "each project rule is distinct")
    }

    // MARK: - Tools

    static func testTools() {
        for tool in CleanupTool.allCases {
            let target = CleanupCatalog.target(tool.target)
            expect(CleanupTool(target: tool.target) == tool, "\(tool) round-trips through its target")
            expect(target.tier == .review && target.disposition == .command, "\(tool) is a reviewed command")
            expect(target.category == .tools, "\(tool) is listed under tool resources")
        }
        expect(CleanupTool.docker.arguments() == ["system", "prune", "--force"], "Docker never prunes volumes")
        expect(CleanupTool.homebrew.arguments() == ["cleanup", "--prune=all"], "Homebrew cleans with its own command")
        expect(CleanupTool.localSnapshots.arguments() == nil, "deleting a snapshot needs its date")
        expect(
            CleanupTool.localSnapshots.arguments(snapshot: "2026-10-17-101500")
                == ["deletelocalsnapshots", "2026-10-17-101500"],
            "a snapshot date passes through exactly")
        expect(CleanupTool.localSnapshots.arguments(snapshot: "/") == nil, "a mount point is never an argument")
        expect(CleanupTool.localSnapshots.arguments(snapshot: "2026-10-17-1015; rm") == nil, "nothing else rides along")
        let listing = """
            Snapshots for disk /:
            com.apple.TimeMachine.2026-10-15-080000.local
            com.apple.TimeMachine.2026-10-17-101500.local
            com.apple.os.update-ABCDEF
            com.apple.TimeMachine.2026-10-16-090000.local
            """
        expect(
            CleanupTool.removableSnapshots(fromListing: listing) == ["2026-10-15-080000", "2026-10-16-090000"],
            "only Time Machine's snapshots, keeping the newest")
        let simctl = Data(
            """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-16-0":[
              {"udid":"11111111-2222-3333-4444-555555555555","name":"iPhone 14","isAvailable":false},
              {"udid":"not-a-udid","name":"Bad","isAvailable":false},
              {"udid":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"iPhone 15","isAvailable":true}]}}
            """.utf8)
        let devices = CleanupTool.unavailableDevices(fromJSON: simctl)
        expect(devices.map(\.udid) == ["11111111-2222-3333-4444-555555555555"], "only unavailable, well-formed devices")
        let df = """
            {"Type":"Images","Reclaimable":"1.5GB (60%)"}
            {"Type":"Containers","Reclaimable":"0B (0%)"}
            {"Type":"Build Cache","Reclaimable":"512MB"}
            """
        expect(CleanupTool.dockerReclaimable(fromOutput: df) == 2_012_000_000, "Docker's reclaimable bytes add up")
        expect(CleanupTool.dockerReclaimable(fromOutput: "error") == nil, "no rows means nothing is known")
        expect(CleanupDeletionMode.trashOnly.resolve(.command) == .command, "trash-only mode leaves tools to their tool")
        expect(refusal("Library/Caches/Homebrew") == .notInCatalog, "Homebrew's cache is never a generic row")
    }

    // MARK: - System updates

    static func updateVerdict(
        _ path: String, modifiedDaysBeforeBoot days: Double = 2, pending: Set<String> = [], restricted: Bool = false,
        resolvedParent: String? = nil
    ) -> CleanupVerdict {
        let boot = now
        let evidence = CleanupSystemUpdateEvidence(
            modified: boot.addingTimeInterval(-days * 86_400), bootTime: boot, pendingProducts: pending,
            isRestricted: restricted)
        let context = CleanupPathContext(
            home: home, resolvedHome: home,
            resolvedParent: resolvedParent ?? (path as NSString).deletingLastPathComponent,
            evidence: .systemUpdate(evidence))
        return CleanupSafetyPolicy.evaluate(path: path, expected: .systemUpdates, context: context)
    }

    static func isAllowed(_ verdict: CleanupVerdict) -> Bool {
        if case .allowed = verdict { return true }
        return false
    }

    static func testSystemUpdates() {
        let bundle = CleanupSystemUpdatePolicy.installData + "/UpdateBundle"
        expect(isAllowed(updateVerdict(bundle)), "a staged update older than the last boot is a leftover")
        expect(!isAllowed(updateVerdict(bundle, modifiedDaysBeforeBoot: -1)), "one staged since boot waits on a restart")
        expect(!isAllowed(updateVerdict(bundle, pending: ["042-12345"])), "a pending product keeps the staging area")
        expect(!isAllowed(updateVerdict(bundle, restricted: true)), "SIP-restricted items are never offered")
        expect(
            !isAllowed(updateVerdict(CleanupSystemUpdatePolicy.installData + "/Locked Files")),
            "Locked Files is always kept")
        expect(!isAllowed(updateVerdict(CleanupSystemUpdatePolicy.installData)), "the staging folder itself stays")
        expect(isAllowed(updateVerdict("/Library/Updates/042-12345")), "an unreferenced old product folder goes")
        expect(
            !isAllowed(updateVerdict("/Library/Updates/042-12345", pending: ["042-12345"])),
            "a product index.plist lists stays")
        expect(!isAllowed(updateVerdict("/Library/Updates/index.plist")), "softwareupdate's index stays")
        expect(!isAllowed(updateVerdict("/Library/Updates/ProductMetadata.plist")), "its metadata stays")
        expect(!isAllowed(updateVerdict("/Library/Updates/a b")), "a name with a space is never handed to a shell")
        expect(!isAllowed(updateVerdict("/Library/Updates/../Keychains")), "dot segments are refused")
        expect(!isAllowed(updateVerdict("/System/Library/CoreServices/x")), "nothing else outside home qualifies")
        expect(!isAllowed(updateVerdict("/Library/Updates/042", resolvedParent: "/private/tmp")), "a symlinked parent")
        expect(
            CleanupSafetyPolicy.evaluate(path: bundle, context: context(for: bundle)) == .refused(.outsideHome),
            "without its evidence an update file is just a path outside home")
        expect(
            CleanupSystemUpdatePolicy.pendingProducts(
                fromIndex: ["ProductPaths": ["042-12345": "042-12345/042-12345.pkg"]]) == ["042-12345", "042-12345.pkg"],
            "pending products are read from both keys and values")
        let script = CleanupSystemUpdatePolicy.removalScript(paths: [bundle], prompt: "Say \"hi\"")
        expect(
            script == "do shell script \"/bin/rm -rf -- '\(bundle)'\" with prompt \"Say \\\"hi\\\"\" "
                + "with administrator privileges",
            "the privileged script quotes the path and escapes the prompt")
        expect(
            CleanupSystemUpdatePolicy.removalScript(paths: ["/etc/passwd"], prompt: "x") == nil,
            "the script builder refuses anything but an approved leaf")
        expect(CleanupSystemUpdatePolicy.removalScript(paths: [], prompt: "x") == nil, "an empty run builds nothing")
    }

    // MARK: - Files

    static func fileVerdict(
        _ path: String, kind: CleanupFileKind, bytes: Int64 = 5_000, usedDaysAgo days: Double = 3,
        isRegularFile: Bool = true, keeper: String? = nil, matches: Bool = false, bundleID: String? = nil,
        resolvedParent: String? = nil
    ) -> CleanupVerdict {
        let evidence = CleanupFileEvidence(
            kind: kind, bytes: bytes, lastUsed: now.addingTimeInterval(-days * 86_400), isRegularFile: isRegularFile,
            keeper: keeper, matchesKeeper: matches, bundleID: bundleID,
            largeThreshold: CleanupFilePolicy.defaultLargeThreshold, now: now)
        let context = CleanupPathContext(
            home: home, resolvedHome: home,
            resolvedParent: resolvedParent ?? (path as NSString).deletingLastPathComponent, evidence: .file(evidence))
        return CleanupSafetyPolicy.evaluate(path: path, expected: kind.target, context: context)
    }

    static func testFiles() {
        for kind in CleanupFileKind.allCases {
            let target = CleanupCatalog.target(kind.target)
            expect(target.tier == .review && target.disposition == .trash, "\(kind) is reviewed and trashed")
        }
        for id in [CleanupTargetID.aiModels, .virtualMachines, .iosBackups] {
            let target = CleanupCatalog.target(id)
            expect(target.tier == .review && target.disposition == .trash, "\(id) is reviewed and trashed")
        }
        expect(isAllowed(fileVerdict(home + "/Downloads/App.dmg", kind: .installer)), "a disk image in Downloads")
        expect(isAllowed(fileVerdict(home + "/Desktop/old/Setup.pkg", kind: .installer)), "nested in Desktop")
        expect(!isAllowed(fileVerdict(home + "/Pictures/App.dmg", kind: .installer)), "Pictures is never walked")
        expect(!isAllowed(fileVerdict(home + "/Library/App.dmg", kind: .installer)), "nor Library")
        expect(!isAllowed(fileVerdict(home + "/Downloads/.cache/App.dmg", kind: .installer)), "nor a hidden folder")
        expect(
            !isAllowed(fileVerdict(home + "/Movies/My.fcpbundle/Render.mov", kind: .large, bytes: 2 << 30)),
            "nothing inside a package")
        expect(!isAllowed(fileVerdict(home + "/Downloads/App.zip", kind: .installer)), "a zip is not an installer")
        expect(
            !isAllowed(fileVerdict(home + "/Downloads/a.crdownload", kind: .incompleteDownload, usedDaysAgo: 0.1)),
            "a download from this morning may still run")
        expect(
            isAllowed(fileVerdict(home + "/Downloads/a.crdownload", kind: .incompleteDownload, usedDaysAgo: 2)),
            "a stalled one is offered")
        expect(isAllowed(fileVerdict(home + "/Movies/a.mov", kind: .large, bytes: 2 << 30)), "a 2 GB file is large")
        expect(!isAllowed(fileVerdict(home + "/Movies/a.mov", kind: .large, bytes: 2 << 20)), "2 MB is not")
        expect(
            isAllowed(fileVerdict(home + "/Documents/a.zip", kind: .old, bytes: 200 << 20, usedDaysAgo: 400)),
            "200 MB untouched for 400 days is old")
        expect(
            !isAllowed(fileVerdict(home + "/Documents/a.zip", kind: .old, bytes: 200 << 20, usedDaysAgo: 30)),
            "used last month is not")
        let keeper = home + "/Documents/a.mov"
        expect(
            isAllowed(fileVerdict(home + "/Downloads/a.mov", kind: .duplicate, keeper: keeper, matches: true)),
            "a confirmed copy is a duplicate")
        expect(
            !isAllowed(fileVerdict(home + "/Downloads/a.mov", kind: .duplicate, keeper: keeper, matches: false)),
            "an unconfirmed copy is not")
        expect(
            !isAllowed(fileVerdict(keeper, kind: .duplicate, keeper: keeper, matches: true)), "the keeper never is")
        expect(
            fileVerdict(home + "/Downloads/App.dmg", kind: .installer) != .refused(.neverDelete),
            "the never-delete roots yield only to a personal file's own evidence")
        expect(refusal("Downloads/App.dmg") == .neverDelete, "a catalog lookup still refuses Downloads")
        let installer = "/Applications/Install macOS Tahoe.app"
        expect(
            isAllowed(
                fileVerdict(
                    installer, kind: .macOSInstaller, isRegularFile: false, bundleID: "com.apple.InstallAssistant.Tahoe")),
            "a macOS installer in Applications")
        expect(
            !isAllowed(fileVerdict(installer, kind: .macOSInstaller, isRegularFile: false, bundleID: "com.evil.app")),
            "only Apple's installer assistant")
        expect(
            !isAllowed(
                fileVerdict(
                    "/Applications/Safari.app", kind: .macOSInstaller, isRegularFile: false,
                    bundleID: "com.apple.InstallAssistant.Tahoe")),
            "only an app named as an installer")
        expect(target("Library/Application Support/MobileSync/Backup/00008110-0001") == .iosBackups, "a device backup")
        expect(
            refusal("Library/Application Support/MobileSync/Library") == .neverDelete,
            "the rest of MobileSync stays never-delete")
        expect(target(".ollama/models") == .aiModels, "Ollama's models")
        expect(target("Parallels/Windows 11.pvm") == .virtualMachines, "a Parallels machine")
        let copies = [(home + "/b/a.mov", now), (home + "/a.mov", now.addingTimeInterval(-10))]
        expect(CleanupFilePolicy.keeper(of: copies) == home + "/a.mov", "the earliest copy is kept")
    }

    // MARK: - Leftovers

    static func leftover(
        _ kind: CleanupLeftoverKind, _ identifier: String, registered: Bool = false, known: Set<String> = [],
        idleDays: Double = 60, program: String? = nil, programExists: Bool = false, obsolete: Bool = false,
        kept: Set<String> = []
    ) -> CleanupLeftoverEvidence {
        CleanupLeftoverEvidence(
            kind: kind, identifier: identifier, isRegistered: registered, knownIdentifiers: known,
            lastModified: now.addingTimeInterval(-idleDays * 86_400), program: program, programExists: programExists,
            listedObsolete: obsolete, keptVersions: kept, now: now)
    }

    static func leftoverVerdict(_ relative: String, _ evidence: CleanupLeftoverEvidence) -> CleanupVerdict {
        let path = home + "/" + relative
        var context = context(for: path)
        context.evidence = .leftover(evidence)
        return CleanupSafetyPolicy.evaluate(path: path, expected: evidence.kind.target, context: context)
    }

    static func testLeftovers() {
        expect(CleanupLeftoverPolicy.decide(leftover(.appData, "com.gone.App")), "an unowned idle folder is a leftover")
        expect(!CleanupLeftoverPolicy.decide(leftover(.appData, "com.gone.App", registered: true)), "LaunchServices knows it")
        expect(
            !CleanupLeftoverPolicy.decide(leftover(.appData, "com.vendor.App.helper", known: ["com.vendor.app"])),
            "a helper's folder belongs to its installed app")
        expect(
            !CleanupLeftoverPolicy.decide(leftover(.appData, "com.vendor.app", known: ["com.vendor.app.agent"])),
            "an installed helper keeps its parent's folder")
        expect(
            CleanupLeftoverPolicy.decide(leftover(.appData, "com.vendor.ap", known: ["com.vendor.app"])),
            "a name that only shares letters is not related")
        expect(!CleanupLeftoverPolicy.decide(leftover(.appData, "com.gone.App", idleDays: 3)), "written to this week")
        expect(!CleanupLeftoverPolicy.decide(leftover(.appData, "com.apple.Notes")), "never Apple's own")
        expect(!CleanupLeftoverPolicy.decide(leftover(.appData, "com.apple.akd")), "never an identity folder")
        expect(!CleanupLeftoverPolicy.decide(leftover(.appData, "com.1password.1password")), "never a password manager")
        expect(!CleanupLeftoverPolicy.decide(leftover(.appData, "Google")), "a plain name is not evidence of anything")
        expect(
            CleanupLeftoverPolicy.decide(leftover(.launchAgent, "com.gone.agent", program: "/Applications/Gone.app/x")),
            "an agent whose program is gone")
        expect(
            !CleanupLeftoverPolicy.decide(leftover(.launchAgent, "com.ok.agent", program: "/x", programExists: true)),
            "an agent whose program exists")
        expect(
            !CleanupLeftoverPolicy.decide(leftover(.launchAgent, "com.os.agent", program: "/usr/libexec/gone")),
            "a missing system program is the OS's business")
        expect(CleanupLeftoverPolicy.decide(leftover(.editorExtension, "ms-python.python-1.0", obsolete: true)), "obsolete")
        expect(!CleanupLeftoverPolicy.decide(leftover(.editorExtension, "ms-python.python-2.0")), "an installed extension")
        expect(
            CleanupLeftoverPolicy.keptVersions(names: ["2.1.1", "2.1.3", "2.1.2", "beta"], linkTarget: "/v/2.1.2")
                == ["2.1.3", "2.1.2", "beta"],
            "the newest, the linked and any unreadable version are kept")
        expect(CleanupLeftoverPolicy.decide(leftover(.cliVersion, "2.1.1", kept: ["2.1.3"])), "an old CLI version")
        expect(!CleanupLeftoverPolicy.decide(leftover(.cliVersion, "2.1.1", kept: [])), "nothing proven, nothing offered")
        expect(
            CleanupLeftoverPolicy.obsoleteExtensions(fromJSON: Data(#"{"a-1.0":true,"b-2.0":false}"#.utf8)) == ["a-1.0"],
            "only entries the editor marked true")

        expect(
            isAllowed(leftoverVerdict("Library/Application Support/com.gone.App", leftover(.appData, "com.gone.App"))),
            "the gate allows an evidenced leftover")
        expect(
            !isAllowed(leftoverVerdict("Library/Preferences/com.gone.App", leftover(.appData, "com.gone.App"))),
            "Preferences stays never-delete")
        expect(
            !isAllowed(leftoverVerdict("Library/Group Containers/com.gone.App", leftover(.appData, "com.gone.App"))),
            "Group Containers stay never-delete")
        expect(
            !isAllowed(leftoverVerdict("Library/Application Support/com.other.App", leftover(.appData, "com.gone.App"))),
            "evidence for one folder never vouches for another")
        expect(
            isAllowed(
                leftoverVerdict(
                    "Library/LaunchAgents/com.gone.agent.plist",
                    leftover(.launchAgent, "com.gone.agent", program: "/Applications/Gone.app/x"))),
            "the gate allows a dead agent's plist")
        expect(
            !isAllowed(
                leftoverVerdict(
                    "Library/LaunchAgents/com.gone.agent.plist",
                    leftover(.launchAgent, "com.gone.agent", program: "/Applications/Gone.app/x", programExists: true))),
            "and re-decides it from fresh evidence")
    }

    static func testCloud() {
        let good = CleanupCloudEvidence(
            isUbiquitous: true, isCurrent: true, isUploaded: true, isUploading: false, hasConflicts: false,
            bytes: 50 << 20)
        expect(CleanupCloudPolicy.qualifies(good), "an uploaded, current download qualifies")
        let variants = [
            CleanupCloudEvidence(
                isUbiquitous: true, isCurrent: true, isUploaded: false, isUploading: false, hasConflicts: false,
                bytes: 50 << 20),
            CleanupCloudEvidence(
                isUbiquitous: true, isCurrent: true, isUploaded: true, isUploading: true, hasConflicts: false,
                bytes: 50 << 20),
            CleanupCloudEvidence(
                isUbiquitous: true, isCurrent: true, isUploaded: true, isUploading: false, hasConflicts: true,
                bytes: 50 << 20),
            CleanupCloudEvidence(
                isUbiquitous: true, isCurrent: false, isUploaded: true, isUploading: false, hasConflicts: false,
                bytes: 50 << 20)
        ]
        for evidence in variants { expect(!CleanupCloudPolicy.qualifies(evidence), "only a file iCloud fully holds") }
        let path = home + "/Library/Mobile Documents/com~apple~CloudDocs/Movies/Trip.mov"
        var context = context(for: path)
        context.evidence = .cloud(good)
        expect(
            isAllowed(CleanupSafetyPolicy.evaluate(path: path, expected: .iCloudDownloads, context: context)),
            "the gate lets a download go")
        expect(
            refusal("Library/Mobile Documents/com~apple~CloudDocs/Movies/Trip.mov") == .neverDelete,
            "without evidence iCloud Drive stays never-delete")
        expect(CleanupCatalog.target(.iCloudDownloads).disposition == .evict, "a download is evicted, never deleted")
        expect(CleanupDeletionMode.trashOnly.resolve(.evict) == .evict, "trash-only mode still only evicts")
    }

    static func testDiskUsage() {
        var level = DiskUsageLevel(
            path: home, title: "tester",
            entries: [
                DiskUsageEntry(path: home + "/a", name: "a", kind: .folder),
                DiskUsageEntry(path: home + "/b", name: "b", kind: .folder),
                DiskUsageEntry(path: home + "/c.txt", name: "c.txt", kind: .file, bytes: 10),
                DiskUsageEntry(path: home + "/Documents", name: "Documents", kind: .guarded)
            ])
        level.setSize(5, isPartial: false, forPath: home + "/a")
        expect(level.entries.map(\.name) == ["a", "b", "c.txt", "Documents"], "rows keep their order while sizes land")
        level.setSize(100, isPartial: false, forPath: home + "/b")
        expect(level.isComplete, "a guarded row never holds a level open")
        expect(level.entries.map(\.name) == ["b", "c.txt", "a", "Documents"], "largest first once every size is in")
        expect(level.total == 115, "the level totals what it measured")
        expect(abs(level.fraction(of: level.entries[0]) - 100.0 / 115.0) < 0.0001, "a row's share of its folder")
        level.attribute(used: 200, title: "Other")
        expect(level.entries.first { $0.kind == .unattributed }?.bytes == 85, "the rest is attributed")
        level.attribute(used: 400, title: "Other")
        expect(level.entries.filter { $0.kind == .unattributed }.count == 1, "attributed once")
        expect(DiskUsagePolicy.canTrash(home + "/Downloads/big.iso", home: home), "a file in Downloads can go")
        expect(!DiskUsagePolicy.canTrash(home + "/Downloads", home: home), "a top-level folder can't")
        expect(!DiskUsagePolicy.canTrash(home + "/Library/Caches/x", home: home), "nothing in Library")
        expect(!DiskUsagePolicy.canTrash(home + "/.ssh/id_ed25519", home: home), "nothing hidden")
        expect(!DiskUsagePolicy.canTrash("/Applications/Xcode.app", home: home), "nothing outside home")
    }

    static func testSchedule() {
        let day: TimeInterval = 86_400
        expect(
            CleanupSchedule.wait(lastRun: nil, enabledAt: now, interval: .weekly, now: now) == 7 * day,
            "the first run is a full interval after switching on")
        expect(
            CleanupSchedule.wait(lastRun: now.addingTimeInterval(-8 * day), enabledAt: now, interval: .weekly, now: now)
                == -day,
            "a missed run is overdue, not skipped")
        expect(CleanupSpaceAlert.shouldAlert(available: 4_000_000_000, thresholdGB: 10, wasLow: false), "crossing alerts")
        expect(!CleanupSpaceAlert.shouldAlert(available: 4_000_000_000, thresholdGB: 10, wasLow: true), "once per crossing")
        expect(!CleanupSpaceAlert.shouldAlert(available: 40_000_000_000, thresholdGB: 10, wasLow: false), "room is quiet")
        var history: [CleanupHistoryEntry] = []
        for index in 0..<120 {
            history = CleanupHistory.appending(
                CleanupHistoryEntry(date: now, bytes: Int64(index), count: 1, isAutomatic: false), to: history)
        }
        expect(history.count == CleanupHistory.limit, "history keeps the newest runs only")
        expect(
            CleanupHistory.appending(CleanupHistoryEntry(date: now, bytes: 0, count: 0, isAutomatic: true), to: []).isEmpty,
            "a run that removed nothing leaves no entry")
        let automatic = CleanupCatalog.targets.filter { $0.tier == .safe && $0.disposition == .delete }
        expect(automatic.allSatisfy { $0.source == .catalog || $0.source == .project }, "automatic runs take only audited rows")
        expect(!automatic.contains { $0.category == .files || $0.category == .leftovers }, "never a personal file or leftover")
    }

    static func main() {
        testSchedule()
        testDiskUsage()
        testCloud()
        testLeftovers()
        testFiles()
        testSystemUpdates()
        testTools()
        testProjectPolicy()
        testNeverDeleteRoots()
        testOutsideHome()
        testPathSpellings()
        testSymlinkedAncestors()
        testProtectedNames()
        testOwnApp()
        testJetBrains()
        testAuditNarrowings()
        testNeverSafe()
        testCacheClassification()
        testCatalogAudit()
        testBrowsers()
        testRunningOwners()
        testSelection()
        testGroupToggle()
        testStreamedSizes()
        testAutomaticItems()
        testKeepNewest()
        testDeletionMode()
        testReport()
        testNaming()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
