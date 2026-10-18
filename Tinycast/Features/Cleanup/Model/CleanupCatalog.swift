// Adapted from Purge (MIT): https://github.com/jithin-sabu/purge-app/blob/main/LICENSE
import Foundation

/// What a leaf path resolves to; exactly one target owns any offered path.
struct CleanupMatch: Hashable, Sendable {
    let target: CleanupTargetID
    let pattern: CleanupPattern
    /// What each `*` stood for, in order.
    let captures: [String]
    /// A child of a `contentsOnly` leaf, which is what the runner removes.
    let isContentsChild: Bool

    /// The cache folder or container ID a generic leaf is named for.
    var key: String? { captures.first }
}

enum CleanupCacheClass: Equatable, Sendable {
    case recognized
    case unknown
    case protected
}

/// The audited target list. docs/features/cleanup.md carries each entry's reasoning.
enum CleanupCatalog {
    static let targets: [CleanupTarget] = system + browsers + developer + tools + projects + files + leftovers + [trash]

    static func target(_ id: CleanupTargetID) -> CleanupTarget {
        guard let target = targets.first(where: { $0.id == id }) else {
            preconditionFailure("missing catalog target \(id)")
        }
        return target
    }

    // MARK: - System

    private static let system: [CleanupTarget] = [
        CleanupTarget(
            id: .systemUpdates, category: .system, tier: .review, disposition: .administrator, patterns: [],
            source: .systemUpdate),
        CleanupTarget(
            id: .appCaches, category: .system, tier: .safe, disposition: .delete,
            patterns: genericCachePatterns, isGeneric: true),
        CleanupTarget(
            id: .otherAppCaches, category: .system, tier: .review, disposition: .trash,
            patterns: genericCachePatterns, isGeneric: true),
        CleanupTarget(
            id: .logs, category: .system, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Logs/*")]),
        CleanupTarget(
            id: .crashReports, category: .system, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Logs/DiagnosticReports/*")]),
        CleanupTarget(
            id: .savedState, category: .system, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Saved Application State/*")],
            minimumAge: 30 * 86_400),
        CleanupTarget(
            id: .deviceFirmware, category: .system, tier: .safe, disposition: .delete,
            patterns: [
                CleanupPattern("Library/iTunes/iPhone Software Updates/*"),
                CleanupPattern("Library/iTunes/iPad Software Updates/*"),
                CleanupPattern("Library/iTunes/iPod Software Updates/*")
            ]),
        CleanupTarget(
            id: .messagesPreviews, category: .system, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Messages/Caches/Previews", contentsOnly: true)],
            ownerBundleIDs: ["com.apple.MobileSMS"])
    ]

    private static let genericCachePatterns = [
        CleanupPattern("Library/Caches/*"),
        CleanupPattern("Library/Containers/*/Data/Library/Caches", contentsOnly: true)
    ]

    // MARK: - Browsers

    private static let browsers: [CleanupTarget] = [
        CleanupTarget(
            id: .safari, category: .browsers, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Caches/com.apple.Safari", label: "Safari")],
            ownerBundleIDs: ["com.apple.Safari"]),
        chromium(
            .chrome, label: "Chrome", support: "Google/Chrome", caches: ["Google/Chrome"],
            owner: "com.google.Chrome"),
        chromium(
            .edge, label: "Microsoft Edge", support: "Microsoft Edge", caches: ["Microsoft Edge"],
            owner: "com.microsoft.edgemac"),
        chromium(
            .brave, label: "Brave", support: "BraveSoftware/Brave-Browser",
            caches: ["BraveSoftware/Brave-Browser"], owner: "com.brave.Browser"),
        chromium(
            .arc, label: "Arc", support: "Arc/User Data", caches: ["Arc", "company.thebrowser.Browser"],
            owner: "company.thebrowser.Browser"),
        chromium(
            .vivaldi, label: "Vivaldi", support: "Vivaldi", caches: ["Vivaldi"],
            owner: "com.vivaldi.Vivaldi"),
        chromium(
            .opera, label: "Opera", support: "com.operasoftware.Opera",
            caches: ["com.operasoftware.Opera"], owner: "com.operasoftware.Opera"),
        CleanupTarget(
            id: .firefox, category: .browsers, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Caches/Firefox", label: "Firefox")],
            ownerBundleIDs: ["org.mozilla.firefox"]),
        // A site's offline data lives here too, so it is never cleared without a look.
        CleanupTarget(
            id: .serviceWorkers, category: .browsers, tier: .review, disposition: .trash,
            patterns: chromiumBrowsers.flatMap { browser in
                ["CacheStorage", "ScriptCache"].map {
                    CleanupPattern(
                        "Library/Application Support/\(browser.support)/*/Service Worker/\($0)",
                        label: browser.label)
                }
            },
            ownerBundleIDs: chromiumBrowsers.map(\.owner))
    ]

    private static let chromiumBrowsers: [(support: String, label: String, owner: String)] = [
        ("Google/Chrome", "Chrome", "com.google.Chrome"),
        ("Microsoft Edge", "Microsoft Edge", "com.microsoft.edgemac"),
        ("BraveSoftware/Brave-Browser", "Brave", "com.brave.Browser"),
        ("Arc/User Data", "Arc", "company.thebrowser.Browser"),
        ("Vivaldi", "Vivaldi", "com.vivaldi.Vivaldi"),
        ("com.operasoftware.Opera", "Opera", "com.operasoftware.Opera")
    ]

    /// Chromium keeps GPU and code caches per profile, outside `~/Library/Caches`.
    private static let chromiumProfileCaches = [
        "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache"
    ]

    private static let chromiumRootCaches = [
        "GrShaderCache", "ShaderCache", "GraphiteDawnCache", "component_crx_cache"
    ]

    private static func chromium(
        _ id: CleanupTargetID, label: String, support: String, caches: [String], owner: String
    ) -> CleanupTarget {
        let base = "Library/Application Support/" + support
        let patterns =
            caches.map { CleanupPattern("Library/Caches/" + $0, label: label) }
            + chromiumProfileCaches.map { CleanupPattern("\(base)/*/\($0)", label: label) }
            + chromiumRootCaches.map { CleanupPattern("\(base)/\($0)", label: label) }
            + [CleanupPattern("\(base)/Crashpad/completed", label: "Crashpad", contentsOnly: true)]
        return CleanupTarget(
            id: id, category: .browsers, tier: .safe, disposition: .delete, patterns: patterns,
            ownerBundleIDs: [owner])
    }

    // MARK: - Developer

    private static let developer: [CleanupTarget] = [
        CleanupTarget(
            id: .derivedData, category: .developer, tier: .safe, disposition: .delete,
            patterns: [CleanupPattern("Library/Developer/Xcode/DerivedData/*")],
            ownerBundleIDs: ["com.apple.dt.Xcode"], ownerProcesses: ["xcodebuild", "swift-build"]),
        CleanupTarget(
            id: .xcodeCaches, category: .developer, tier: .safe, disposition: .delete,
            patterns: [
                CleanupPattern("Library/Caches/com.apple.dt.Xcode", label: "Xcode"),
                CleanupPattern("Library/Developer/Xcode/DocumentationCache", label: "Xcode"),
                CleanupPattern("Library/Developer/XCTestDevices", label: "XCTest"),
                CleanupPattern("Library/Developer/Xcode/UserData/Previews", label: "Previews")
            ],
            ownerBundleIDs: ["com.apple.dt.Xcode"], ownerProcesses: ["xcodebuild"]),
        CleanupTarget(
            id: .deviceSupport, category: .developer, tier: .safe, disposition: .delete,
            patterns: ["iOS", "watchOS", "tvOS", "visionOS", "xrOS", "macOS"].map { (platform: String) in
                CleanupPattern("Library/Developer/Xcode/\(platform) DeviceSupport/*", label: platform)
            },
            ownerBundleIDs: ["com.apple.dt.Xcode"], keepNewest: 2),
        // The dSYMs inside are what symbolicate a shipped build's crash reports.
        CleanupTarget(
            id: .xcodeArchives, category: .developer, tier: .review, disposition: .trash,
            patterns: [CleanupPattern("Library/Developer/Xcode/Archives/*")],
            ownerBundleIDs: ["com.apple.dt.Xcode"]),
        CleanupTarget(
            id: .simulatorCaches, category: .developer, tier: .safe, disposition: .delete,
            patterns: [
                CleanupPattern("Library/Developer/CoreSimulator/Caches", label: "CoreSimulator"),
                CleanupPattern("Library/Caches/com.apple.iphonesimulator", label: "Simulator")
            ],
            ownerBundleIDs: ["com.apple.iphonesimulator"]),
        CleanupTarget(
            id: .packageCaches, category: .developer, tier: .safe, disposition: .delete,
            patterns: packageCachePatterns,
            ownerProcesses: [
                "npm", "npx", "yarn", "bun", "deno", "pip", "pip3", "uv", "poetry", "cargo",
                "composer", "pod", "carthage", "gem", "bundle", "dart", "flutter", "mix",
                "rebar3", "swift-build", "pre-commit"
            ]),
        CleanupTarget(
            id: .packageStores, category: .developer, tier: .review, disposition: .trash,
            patterns: packageStorePatterns,
            ownerProcesses: ["gradle", "java", "mvn", "dotnet", "stack", "cabal", "bazel", "node"]),
        CleanupTarget(
            id: .editorCaches, category: .developer, tier: .safe, disposition: .delete,
            patterns: editorPatterns,
            ownerBundleIDs: [
                "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.jetbrains"
            ],
            excludedNames: ["localhistory"])
    ]

    private static let packageCachePatterns = [
        CleanupPattern(".npm/_cacache", label: "npm"),
        CleanupPattern(".npm/_npx", label: "npx"),
        CleanupPattern(".npm/_logs", label: "npm logs"),
        CleanupPattern("Library/Caches/Yarn", label: "Yarn"),
        CleanupPattern(".yarn/berry/cache", label: "Yarn"),
        CleanupPattern(".bun/install/cache", label: "Bun"),
        CleanupPattern("Library/Caches/deno", label: "Deno"),
        CleanupPattern(".cache/node/corepack", label: "Corepack"),
        CleanupPattern("Library/Caches/pip", label: "pip"),
        CleanupPattern(".cache/uv", label: "uv"),
        CleanupPattern("Library/Caches/pypoetry/cache", label: "Poetry"),
        CleanupPattern("Library/Caches/pypoetry/artifacts", label: "Poetry"),
        CleanupPattern(".cargo/registry", label: "Cargo"),
        CleanupPattern(".cargo/git", label: "Cargo"),
        CleanupPattern("Library/Caches/composer", label: "Composer"),
        CleanupPattern(".composer/cache", label: "Composer"),
        CleanupPattern("Library/Caches/CocoaPods", label: "CocoaPods"),
        CleanupPattern("Library/Caches/org.carthage.CarthageKit", label: "Carthage"),
        CleanupPattern(".gem/specs", label: "RubyGems"),
        CleanupPattern(".gem/ruby/*/cache", label: "RubyGems"),
        CleanupPattern(".bundle/cache", label: "Bundler"),
        CleanupPattern(".pub-cache/hosted", label: "Dart"),
        CleanupPattern(".pub-cache/git", label: "Dart"),
        CleanupPattern(".hex/packages", label: "Hex"),
        CleanupPattern(".cache/rebar3", label: "rebar3"),
        CleanupPattern(".cache/prisma", label: "Prisma"),
        CleanupPattern(".cache/pre-commit", label: "pre-commit"),
        CleanupPattern("Library/Caches/node-gyp", label: "node-gyp"),
        CleanupPattern("Library/Caches/typescript", label: "TypeScript"),
        CleanupPattern("Library/Caches/org.swift.swiftpm", label: "SwiftPM"),
        CleanupPattern(".swiftpm/cache", label: "SwiftPM"),
        CleanupPattern(".android/cache", label: "Android"),
        CleanupPattern(".android/build-cache", label: "Android")
    ] + expoCaches.map { CleanupPattern(".expo/\($0)", label: "Expo") }

    /// Every Expo folder except `state.json`, which holds the login.
    private static let expoCaches = [
        "android-apk-cache", "ios-simulator-app-cache", "native-modules-cache", "schema-cache",
        "template-cache", "versions-cache", "expo-go"
    ]

    /// Slow to restore, or holding builds you installed locally, so each is a deliberate pick.
    private static let packageStorePatterns = [
        CleanupPattern(".gradle/caches", label: "Gradle"),
        CleanupPattern(".m2/repository", label: "Maven"),
        CleanupPattern(".nuget/packages", label: "NuGet"),
        CleanupPattern(".stack/pantry", label: "Stack"),
        CleanupPattern(".cabal/packages", label: "Cabal"),
        CleanupPattern(".cache/bazel", label: "Bazel"),
        CleanupPattern("Library/Caches/ms-playwright", label: "Playwright"),
        CleanupPattern(".cache/puppeteer", label: "Puppeteer"),
        CleanupPattern("Library/Caches/Cypress", label: "Cypress"),
        CleanupPattern(".cocoapods/repos", label: "CocoaPods specs")
    ]

    private static let editorPatterns =
        ["Code", "Cursor"].flatMap { editor in
            [
                "Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache",
                "DawnGraphiteCache", "DawnWebGPUCache"
            ].map {
                CleanupPattern(
                    "Library/Application Support/\(editor)/\($0)",
                    label: editor == "Code" ? "VS Code" : editor)
            }
        } + [
            CleanupPattern("Library/Caches/com.microsoft.VSCode", label: "VS Code"),
            CleanupPattern("Library/Caches/com.microsoft.VSCode.ShipIt", label: "VS Code"),
            CleanupPattern("Library/Caches/com.todesktop.230313mzl4w4u92", label: "Cursor"),
            CleanupPattern("Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt", label: "Cursor"),
            CleanupPattern("Library/Caches/Zed", label: "Zed"),
            CleanupPattern("Library/Caches/dev.zed.Zed", label: "Zed"),
            CleanupPattern("Library/Caches/JetBrains/*/*", label: "JetBrains")
        ]

    // MARK: - Trash

    private static let trash = CleanupTarget(
        id: .trash, category: .trash, tier: .review, disposition: .delete,
        patterns: [CleanupPattern(".Trash")], isSelectable: false)

    // MARK: - Tools

    /// Each is cleaned by its own command; none is ever safe, so none is preselected or automatic.
    private static let tools: [CleanupTarget] = CleanupTool.allCases.map { tool in
        CleanupTarget(
            id: tool.target, category: .tools, tier: .review, disposition: .command, patterns: [], source: .tool,
            ownerProcesses: tool.ownerProcesses)
    }

    // MARK: - Projects

    /// Proposed by the project walk; `CleanupProjectPolicy` picks the tier from its evidence.
    private static let projects: [CleanupTarget] = [
        CleanupTarget(
            id: .projectArtifacts, category: .projects, tier: .safe, disposition: .delete, patterns: [],
            source: .project),
        CleanupTarget(
            id: .projectArtifactsReview, category: .projects, tier: .review, disposition: .trash, patterns: [],
            source: .project)
    ]

    // MARK: - Files

    /// Personal files: every one is reviewed and trashed, since only the user knows what they are.
    private static let files: [CleanupTarget] = CleanupFileKind.allCases.map { kind in
        CleanupTarget(
            id: kind.target, category: .files, tier: .review, disposition: .trash, patterns: [],
            source: .personalFile)
    } + [
        CleanupTarget(
            id: .aiModels, category: .files, tier: .review, disposition: .trash,
            patterns: [
                CleanupPattern(".ollama/models", label: "Ollama"),
                CleanupPattern(".cache/huggingface/hub/*", label: "Hugging Face"),
                CleanupPattern(".lmstudio/models/*/*", label: "LM Studio")
            ],
            ownerBundleIDs: ["ai.elementlabs.lmstudio", "com.electron.ollama"], ownerProcesses: ["ollama"]),
        CleanupTarget(
            id: .virtualMachines, category: .files, tier: .review, disposition: .trash,
            patterns: [
                CleanupPattern("Parallels/*", label: "Parallels"),
                CleanupPattern("Virtual Machines.localized/*", label: "VMware Fusion"),
                CleanupPattern("VirtualBox VMs/*", label: "VirtualBox"),
                CleanupPattern("Library/Containers/com.utmapp.UTM/Data/Documents/*", label: "UTM")
            ],
            ownerBundleIDs: [
                "com.parallels.desktop.console", "com.vmware.fusion", "org.virtualbox.app.VirtualBox", "com.utmapp.UTM"
            ]),
        CleanupTarget(
            id: .iCloudDownloads, category: .files, tier: .review, disposition: .evict, patterns: [],
            source: .cloudDownload),
        CleanupTarget(
            id: .iosBackups, category: .files, tier: .review, disposition: .trash,
            patterns: [CleanupPattern("Library/Application Support/MobileSync/Backup/*")],
            ownerBundleIDs: ["com.apple.AMPDevicesAgent"])
    ]

    // MARK: - Leftovers

    /// Proposed only on positive evidence nothing owns them; trashed, since evidence can be wrong.
    private static let leftovers: [CleanupTarget] = [
        CleanupTarget(
            id: .appLeftovers, category: .leftovers, tier: .review, disposition: .trash, patterns: [],
            source: .leftover),
        CleanupTarget(
            id: .brokenLaunchAgents, category: .leftovers, tier: .review, disposition: .trash, patterns: [],
            source: .leftover),
        CleanupTarget(
            id: .obsoleteExtensions, category: .leftovers, tier: .review, disposition: .trash, patterns: [],
            source: .leftover,
            ownerBundleIDs: CleanupLeftoverPolicy.editorExtensionParents.map(\.owner)),
        CleanupTarget(
            id: .oldCLIVersions, category: .leftovers, tier: .review, disposition: .trash, patterns: [],
            source: .leftover,
            ownerProcesses: CleanupLeftoverPolicy.cliVersionParents.map(\.process))
    ]

    // MARK: - Claims

    /// Owned by later phases' commands, so no generic row may delete them directly now.
    static let reservedPatterns = [
        "Library/Caches/Homebrew", "Library/Caches/go-build", "Library/Caches/pnpm",
        "Library/pnpm", ".pnpm-store", "go/pkg/mod", "Library/Caches/com.docker.docker",
        "Library/Containers/com.docker.docker", "Library/Group Containers/group.com.docker",
        "Library/Caches/dev.kdrag0n.MacVirt", "Library/Developer/CoreSimulator/Devices"
    ].map { CleanupPattern($0) }

    /// Exact path, or a match of a specific target or reservation: never a generic leaf.
    static func isClaimed(_ path: [String]) -> Bool {
        if reservedPatterns.contains(where: { $0.covers(path) || $0.contains(path) }) { return true }
        return targets.contains { target in
            !target.isGeneric && target.patterns.contains { $0.covers(path) }
        }
    }

    /// The single target that owns `path`, after exclusions and classification.
    static func resolve(_ path: [String]) -> CleanupMatch? {
        for target in targets where !target.isGeneric {
            if let match = match(path, in: target) { return match }
        }
        if reservedPatterns.contains(where: { $0.covers(path) || $0.contains(path) }) { return nil }
        for pattern in genericCachePatterns {
            let leafLength = pattern.components.count
            let isChild = pattern.contentsOnly && path.count == leafLength + 1
            guard path.count == leafLength || isChild,
                let captures = pattern.captures(Array(path.prefix(leafLength))),
                let key = captures.first
            else { continue }
            if isClaimed(Array(path.prefix(leafLength))) { return nil }
            let id: CleanupTargetID
            switch classifyCache(key) {
            case .recognized: id = .appCaches
            case .unknown: id = .otherAppCaches
            case .protected: return nil
            }
            return CleanupMatch(target: id, pattern: pattern, captures: captures, isContentsChild: isChild)
        }
        return nil
    }

    private static func match(_ path: [String], in target: CleanupTarget) -> CleanupMatch? {
        for pattern in target.patterns {
            let leafLength = pattern.components.count
            let isChild = pattern.contentsOnly && path.count == leafLength + 1
            guard path.count == leafLength || isChild,
                let captures = pattern.captures(Array(path.prefix(leafLength)))
            else { continue }
            let leaf = path[leafLength - 1].lowercased()
            if target.excludedNames.contains(leaf) { return nil }
            if !isChild, isAncestorOfOtherTarget(path, besides: target.id) { return nil }
            return CleanupMatch(
                target: target.id, pattern: pattern, captures: captures, isContentsChild: isChild)
        }
        return nil
    }

    /// `Logs/*` must not swallow `Logs/DiagnosticReports`, which another target lists by file.
    private static func isAncestorOfOtherTarget(_ path: [String], besides id: CleanupTargetID) -> Bool {
        targets.contains { target in
            target.id != id && !target.isGeneric
                && target.patterns.contains { $0.components.count > path.count && $0.literallyCovers(path) }
        }
    }

    // MARK: - Cache classification

    static func classifyCache(_ name: String) -> CleanupCacheClass {
        let lower = name.lowercased()
        if CleanupSafetyPolicy.isProtectedName(lower) { return .protected }
        if recognizedCaches.contains(lower) || lower.hasSuffix(".shipit") { return .recognized }
        return .unknown
    }

    /// Caches whose owner rebuilds them without asking; anything else is a reviewed row.
    static let recognizedCaches: Set<String> = [
        "adobe camera raw", "adobe camera raw 2", "ai.perplexity.cometupdater", "amsdatamigratortool",
        "app.spokenly", "app.spokenly.revenuecat", "appinstallationbinarydeltas",
        "at.eggerapps.postico", "chatmedia", "claude-cli-nodejs", "com.anthropic.claudefordesktop",
        "com.apple.amsengagementd", "com.apple.ap.promotedcontentjetservice",
        "com.apple.applemediaservices", "com.apple.assistantd", "com.apple.assistantservices",
        "com.apple.betaenrollmentagent", "com.apple.businessservicesd", "com.apple.cache_delete",
        "com.apple.chrono", "com.apple.cloudtelemetry", "com.apple.ctcategories.service",
        "com.apple.dictionaryservices", "com.apple.donotdisturbd", "com.apple.featureaccessagent",
        "com.apple.feedbacklogger", "com.apple.fileproviderdaemon.appstoreservice",
        "com.apple.gamed", "com.apple.geoanalyticsd", "com.apple.helpd",
        "com.apple.managedappdistributionagent", "com.apple.networkserviceproxy",
        "com.apple.parsecd", "com.apple.python", "com.apple.remindd", "com.apple.screencaptureui",
        "com.apple.shazamlibrary.cloud", "com.apple.sirittsd", "com.apple.tipsd",
        "com.apple.translationd", "com.apple.videoconference", "com.bohemiancoding.sketch3",
        "com.danpristupov.fork", "com.datadoghq", "com.figma.agent", "com.figma.desktop",
        "com.fournova.tower3", "com.google.android.studio", "com.google.antigravity.shipit",
        "com.google.googleupdater", "com.googlecode.iterm2", "com.granola.app",
        "com.grammarly.projectllama", "com.hnc.discord", "com.insomnia.app", "com.linear",
        "com.loom.desktop", "com.luckymarmot.paw", "com.macpaw.cleanmymac4",
        "com.microsoft.autoupdate.fba", "com.microsoft.edgeupdater", "com.microsoft.excel",
        "com.microsoft.teams2", "com.microsoft.word", "com.mitchellh.ghostty", "com.openai.chat",
        "com.openai.codex", "com.proxyman.nsproxy", "com.raycast.macos",
        "com.runningwithcrayons.alfred", "com.seriflabs.affinitydesigner2",
        "com.seriflabs.affinityphoto2", "com.sindresorhus.lungo", "com.surteesstudios.bartender",
        "com.tinyapp.tableplus", "com.tinyspeck.slackmacgap", "com.torusknot.sourcetreenotmas",
        "com.xnapper.xnapper", "company.thebrowser.browser.helper", "cursor-compile-cache",
        "dev.warp.warp-stable", "gamekit", "google-sdks-events", "imagecache", "io.sentry", "jna",
        "linkthumbnail", "net.telestream.screenflow", "net.whatsapp.whatsapp", "networkcache",
        "notion.id", "org.blenderfoundation.blender", "pl.maketheweb.cleanshotx", "revenuecat",
        "revenuecatfonts", "ru.keepcoder.telegram", "segment", "sentrycrash", "shipit", "siritts",
        "ssu", "us.zoom.xos"
    ]
}
