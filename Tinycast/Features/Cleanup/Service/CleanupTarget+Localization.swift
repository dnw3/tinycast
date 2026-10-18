import Foundation

extension CleanupCategory {
    var title: String {
        switch self {
        case .system: return String(localized: "System & Apps")
        case .browsers: return String(localized: "Browsers")
        case .developer: return String(localized: "Developer")
        case .tools: return String(localized: "Tool Resources")
        case .projects: return String(localized: "Projects")
        case .files: return String(localized: "Files")
        case .leftovers: return String(localized: "Leftovers")
        case .trash: return String(localized: "Trash")
        }
    }
}

extension CleanupTargetID {
    var title: String {
        switch self {
        case .systemUpdates: return String(localized: "Leftover macOS Updates")
        case .appCaches: return String(localized: "App Caches")
        case .otherAppCaches: return String(localized: "Other App Caches")
        case .logs: return String(localized: "App Logs")
        case .crashReports: return String(localized: "Crash Reports")
        case .savedState: return String(localized: "Saved Window State")
        case .deviceFirmware: return String(localized: "Device Firmware")
        case .messagesPreviews: return String(localized: "Messages Previews")
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .vivaldi: return "Vivaldi"
        case .opera: return "Opera"
        case .firefox: return "Firefox"
        case .serviceWorkers: return String(localized: "Website Offline Data")
        case .derivedData: return String(localized: "Xcode Build Data")
        case .xcodeCaches: return String(localized: "Xcode Caches")
        case .deviceSupport: return String(localized: "Old Device Support")
        case .xcodeArchives: return String(localized: "Xcode Archives")
        case .simulatorCaches: return String(localized: "Simulator Caches")
        case .packageCaches: return String(localized: "Package Caches")
        case .packageStores: return String(localized: "Package Stores")
        case .editorCaches: return String(localized: "Editor Caches")
        case .homebrewCache: return String(localized: "Homebrew Downloads")
        case .unavailableSimulators: return String(localized: "Unavailable Simulators")
        case .pnpmStore: return String(localized: "Unused pnpm Packages")
        case .goBuildCache: return String(localized: "Go Build Cache")
        case .goModuleCache: return String(localized: "Go Module Cache")
        case .dockerData: return String(localized: "Unused Docker Data")
        case .localSnapshots: return String(localized: "Old Local Snapshots")
        case .projectArtifacts: return String(localized: "Idle Project Builds")
        case .projectArtifactsReview: return String(localized: "Other Project Builds")
        case .installers: return String(localized: "Installers")
        case .incompleteDownloads: return String(localized: "Unfinished Downloads")
        case .duplicates: return String(localized: "Duplicate Files")
        case .largeFiles: return String(localized: "Large Files")
        case .oldFiles: return String(localized: "Files Unused for a Year")
        case .macOSInstallers: return String(localized: "macOS Installers")
        case .aiModels: return String(localized: "Local AI Models")
        case .virtualMachines: return String(localized: "Virtual Machines")
        case .iosBackups: return String(localized: "iPhone and iPad Backups")
        case .iCloudDownloads: return String(localized: "iCloud Drive Downloads")
        case .appLeftovers: return String(localized: "Removed Apps’ Data")
        case .brokenLaunchAgents: return String(localized: "Broken Launch Agents")
        case .obsoleteExtensions: return String(localized: "Obsolete Editor Extensions")
        case .oldCLIVersions: return String(localized: "Old CLI Versions")
        case .trash: return String(localized: "Trash")
        }
    }

    /// What it is and what removing it costs, in one breath.
    var explanation: String {
        switch self {
        case .systemUpdates:
            return String(
                localized: """
                    An update macOS downloaded and has already installed or abandoned. Nothing waits on it; \
                    removing it asks for your administrator password once.
                    """)
        case .appCaches:
            return String(localized: "Files apps keep to load faster. Each app rebuilds its cache as you use it.")
        case .otherAppCaches:
            return String(
                localized: """
                    Caches Tinycast hasn’t reviewed. Usually safe, but some \
                    apps keep data here, so they go to the Trash.
                    """)
        case .logs:
            return String(localized: "Diagnostic logs apps write as they run. Nothing reads them back.")
        case .crashReports:
            return String(localized: "Reports left behind when an app crashed. macOS has already sent what it needs.")
        case .savedState:
            return String(
                localized: "Window positions for apps you haven’t opened in a month. An app reopens with fresh windows.")
        case .deviceFirmware:
            return String(localized: "iPhone and iPad updates Finder downloaded. They download again when needed.")
        case .messagesPreviews:
            return String(localized: "Link and attachment previews in Messages. Your conversations aren’t touched.")
        case .safari, .chrome, .edge, .brave, .arc, .vivaldi, .opera, .firefox:
            return String(
                localized: """
                    Cached pages, scripts and GPU shaders. History, passwords \
                    and sign-ins stay. Quit the browser to clean.
                    """)
        case .serviceWorkers:
            return String(
                localized: "Data websites store to work offline. Some sites keep unsent drafts here, so it goes to the Trash.")
        case .derivedData:
            return String(localized: "Build products and indexes. Xcode rebuilds a project the next time you open it.")
        case .xcodeCaches:
            return String(localized: "Xcode’s caches, documentation index, test devices and previews. All rebuilt on demand.")
        case .deviceSupport:
            return String(
                localized: """
                    Debug symbols for older iOS versions. The newest two per \
                    platform are kept; others copy again on connect.
                    """)
        case .xcodeArchives:
            return String(
                localized: "Builds you archived for release. Their dSYMs symbolicate crash reports, so they go to the Trash.")
        case .simulatorCaches:
            return String(localized: "Simulator’s shared caches. Your simulators and their apps aren’t touched.")
        case .packageCaches:
            return String(
                localized: "Downloads package managers keep. Installed tools and projects stay; packages download again.")
        case .packageStores:
            return String(
                localized: "Large stores that are slow to restore or hold builds you installed locally, so they go to the Trash.")
        case .editorCaches:
            return String(
                localized: "Code editor caches. Settings, extensions, local history and AI chats stay. Quit the editor to clean.")
        case .homebrewCache:
            return String(
                localized: """
                    Bottles and source Homebrew downloaded. Installed packages \
                    stay; reinstalling downloads again.
                    """)
        case .unavailableSimulators:
            return String(localized: "Simulators for runtimes Xcode no longer has. They can’t run, and simctl removes them.")
        case .pnpmStore:
            return String(localized: "Packages in pnpm’s store that no project links to anymore. pnpm prunes only those.")
        case .goBuildCache:
            return String(localized: "Compiled Go packages. The next build compiles them again.")
        case .goModuleCache:
            return String(localized: "Downloaded Go modules. Builds download them again, which needs the network.")
        case .dockerData:
            return String(
                localized: "Stopped containers, unused networks, dangling images and build cache. Volumes are never touched.")
        case .localSnapshots:
            return String(
                localized: """
                    Time Machine copies kept on this disk between backups. The newest \
                    is kept; your backups aren’t touched.
                    """)
        case .projectArtifacts:
            return String(
                localized: """
                    Dependencies and build output of projects you haven’t touched lately. Each has a lockfile, \
                    so reinstalling brings back the same versions.
                    """)
        case .projectArtifactsReview:
            return String(
                localized: """
                    Rebuildable folders that are slow to restore, have no lockfile, or sit in a project too big \
                    to check, so they go to the Trash.
                    """)
        case .installers:
            return String(localized: "Disk images and packages you downloaded. Once an app is installed, they aren’t needed.")
        case .incompleteDownloads:
            return String(localized: "Downloads that stopped more than a day ago. Browsers start over rather than resume them.")
        case .duplicates:
            return String(
                localized: """
                    Files with identical contents. The earliest copy is kept and never listed; the others go to the \
                    Trash. Clones that share their disk space aren’t listed.
                    """)
        case .largeFiles:
            return String(localized: "Your biggest files. Only you know whether you still need them.")
        case .oldFiles:
            return String(localized: "Files over 100 MB nobody has opened or changed in a year.")
        case .macOSInstallers:
            return String(localized: "Full macOS installers. macOS downloads a new one whenever you need it.")
        case .aiModels:
            return String(localized: "Models Ollama, LM Studio and Hugging Face downloaded. They download again on next use.")
        case .virtualMachines:
            return String(localized: "Whole virtual machines, with everything installed in them. Quit the app to clean.")
        case .iosBackups:
            return String(
                localized: """
                    Local backups of your devices. Keep the newest unless iCloud Backup covers the device; \
                    an older one is often a device you no longer have.
                    """)
        case .iCloudDownloads:
            return String(
                localized: """
                    Local copies of files iCloud Drive already holds in full. Removing a download keeps the file \
                    in iCloud and in Finder; it downloads again when you open it.
                    """)
        case .appLeftovers:
            return String(
                localized: """
                    Data folders named for apps nothing on this Mac provides anymore, untouched for a month. \
                    An app installed somewhere unusual can look removed, so they go to the Trash.
                    """)
        case .brokenLaunchAgents:
            return String(localized: "Background items whose program is gone. They fail at every login.")
        case .obsoleteExtensions:
            return String(localized: "Extension versions the editor itself marked obsolete after updating them.")
        case .oldCLIVersions:
            return String(localized: "Earlier versions of Claude Code and Cursor’s agent. The current and newest stay.")
        case .trash:
            return String(localized: "Items already in the Trash. Emptying it is permanent.")
        }
    }
}

extension CleanupTarget {
    var handling: String {
        if !isSelectable { return String(localized: "Emptied with Empty Trash") }
        if disposition == .command, let tool = CleanupTool(target: id) {
            return String(localized: "Review first · Cleaned by \(tool.executable) itself")
        }
        switch (tier, disposition) {
        case (.safe, .delete): return String(localized: "Safe to clean · Deleted directly")
        case (.safe, .trash): return String(localized: "Safe to clean · Moved to the Trash")
        case (.review, .delete): return String(localized: "Review first · Deleted directly")
        case (.review, .trash): return String(localized: "Review first · Moved to the Trash")
        case (_, .command): return String(localized: "Review first · Cleaned by its own tool")
        case (_, .administrator): return String(localized: "Review first · Removed with your administrator password")
        case (_, .evict): return String(localized: "Review first · Download removed, file stays in iCloud")
        }
    }
}

extension CleanupFailure {
    /// `appName` turns a running owner's bundle ID into the name the user knows.
    func reason(appName: (String) -> String) -> String {
        switch self {
        case .permissionDenied: return String(localized: "Permission denied")
        case .inUse: return String(localized: "In use")
        case .readOnly: return String(localized: "On a read-only volume")
        case .refused: return String(localized: "Skipped for safety")
        case .running(let owner): return String(localized: "\(appName(owner)) is running")
        case .cancelled: return String(localized: "Cancelled")
        case .other(let code): return String(localized: "Error \(code)")
        case .toolFailed(let output): return String(localized: "The tool reported: \(output)")
        case .toolMissing: return String(localized: "The tool is no longer installed")
        }
    }
}

extension CleanupLock {
    func reason(appName: (String) -> String) -> String {
        switch self {
        case .running(let owner): return String(localized: "Quit \(appName(owner)) to clean this.")
        case .projectInUse: return String(localized: "A process is working in this project.")
        case .protection(let protection):
            return protection.lockReason.map { Bundle.main.localizedString(forKey: $0, value: nil, table: nil) }
                ?? String(localized: "Can’t be cleaned right now.")
        }
    }
}

extension CleanupItem {
    /// Blank until every walk lands, so a total never reads lower than it will settle at.
    static func sizeLabel(_ items: [CleanupItem]) -> String {
        guard !items.isEmpty, items.allSatisfy({ $0.size != nil }) else { return "" }
        if items.allSatisfy(\.isSizeUnknown) { return String(localized: "Size unknown") }
        let bytes = items.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let prefix: String
        if items.contains(where: \.isPartial) {
            prefix = "≥ "
        } else if items.contains(where: \.isUpperBound) {
            prefix = "≤ "
        } else {
            prefix = ""
        }
        return prefix + CleanupCoordinator.format(bytes)
    }

    /// A real folder Finder can show; a tool's synthetic identity is not one.
    var isOnDisk: Bool { path.hasPrefix("/") }
}
