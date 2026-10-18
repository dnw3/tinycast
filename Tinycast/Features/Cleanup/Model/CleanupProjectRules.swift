// Adapted from Purge (MIT): https://github.com/jithin-sabu/purge-app/blob/main/LICENSE
import Foundation

/// One rebuildable folder belonging to one kind of project; a rule only ever proposes a path.
struct CleanupProjectRule: Hashable, Sendable {
    /// Brand name shown on the row, never localized.
    let ecosystem: String
    /// Relative to the project root; may hold a subdirectory such as `ios/Pods`.
    let folder: String
    /// Any one of these, relative to the root, makes it this kind of project.
    let rootMarkers: [String]
    /// Extensions that identify the project when no fixed filename does.
    let rootMarkerExtensions: [String]
    /// Any one of these, relative to the root, pins exact versions so a rebuild matches.
    let lockfiles: [String]
    /// A file inside the folder that means it holds real state and is never offered.
    let refuseWhenPresent: [String]
    /// The command or step that brings the folder back, shown in the detail pane.
    let rebuild: String
    /// Rebuilds itself but at real cost, so it is never safe whatever the evidence.
    let alwaysReview: Bool

    init(
        _ ecosystem: String, folder: String, rootMarkers: [String] = [], extensions: [String] = [],
        lockfiles: [String] = [], refuseWhenPresent: [String] = [], rebuild: String, alwaysReview: Bool = false
    ) {
        self.ecosystem = ecosystem
        self.folder = folder
        self.rootMarkers = rootMarkers
        rootMarkerExtensions = extensions
        self.lockfiles = lockfiles
        self.refuseWhenPresent = refuseWhenPresent
        self.rebuild = rebuild
        self.alwaysReview = alwaysReview
    }

    var folderName: String { (folder as NSString).lastPathComponent }
}

enum CleanupProjectRules {
    private static let node = ["package.json"]
    private static let nodeLocks = [
        "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock"
    ]
    private static let nuxt = ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs", "nuxt.config.cjs"]
    private static let python = ["requirements.txt", "pyproject.toml", "setup.py"]
    private static let pythonLocks = ["uv.lock", "poetry.lock", "requirements.txt", "Pipfile.lock", "pdm.lock"]
    private static let gradle = [
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
        "android/build.gradle", "android/build.gradle.kts"
    ]

    static let rules: [CleanupProjectRule] = [
        CleanupProjectRule(
            "Node", folder: "node_modules", rootMarkers: node, lockfiles: nodeLocks, rebuild: "npm install"),
        CleanupProjectRule("Next.js", folder: ".next", rootMarkers: node, lockfiles: nodeLocks, rebuild: "npm run build"),
        CleanupProjectRule("Nuxt", folder: ".nuxt", rootMarkers: nuxt, lockfiles: nodeLocks, rebuild: "npm run build"),
        CleanupProjectRule("Nuxt", folder: ".output", rootMarkers: nuxt, lockfiles: nodeLocks, rebuild: "npm run build"),
        CleanupProjectRule(
            "SvelteKit", folder: ".svelte-kit", rootMarkers: node, lockfiles: nodeLocks, rebuild: "npm run build"),
        CleanupProjectRule("Astro", folder: ".astro", rootMarkers: node, lockfiles: nodeLocks, rebuild: "npm run build"),
        CleanupProjectRule("Angular", folder: ".angular", rootMarkers: node, lockfiles: nodeLocks, rebuild: "ng build"),
        CleanupProjectRule("Turborepo", folder: ".turbo", rootMarkers: node, lockfiles: nodeLocks, rebuild: "turbo run"),
        CleanupProjectRule(
            "Parcel", folder: ".parcel-cache", rootMarkers: node, lockfiles: nodeLocks, rebuild: "parcel build"),
        CleanupProjectRule(
            "Rust", folder: "target", rootMarkers: ["Cargo.toml"], lockfiles: ["Cargo.lock"], rebuild: "cargo build"),
        CleanupProjectRule(
            "Python", folder: ".venv", rootMarkers: python, lockfiles: pythonLocks,
            refuseWhenPresent: ["conda-meta"], rebuild: "uv sync / pip install -r requirements.txt"),
        CleanupProjectRule(
            "Python", folder: "venv", rootMarkers: python, lockfiles: pythonLocks,
            refuseWhenPresent: ["conda-meta"], rebuild: "pip install -r requirements.txt"),
        CleanupProjectRule("pytest", folder: ".pytest_cache", rootMarkers: python, lockfiles: python, rebuild: "pytest"),
        CleanupProjectRule("mypy", folder: ".mypy_cache", rootMarkers: python, lockfiles: python, rebuild: "mypy"),
        CleanupProjectRule("Ruff", folder: ".ruff_cache", rootMarkers: python, lockfiles: python, rebuild: "ruff check"),
        CleanupProjectRule("tox", folder: ".tox", rootMarkers: ["tox.ini"], lockfiles: ["tox.ini"], rebuild: "tox"),
        CleanupProjectRule(
            "Dart", folder: ".dart_tool", rootMarkers: ["pubspec.yaml"], lockfiles: ["pubspec.lock"],
            rebuild: "flutter pub get"),
        CleanupProjectRule(
            "Flutter", folder: "build", rootMarkers: ["pubspec.yaml"], lockfiles: ["pubspec.lock"],
            rebuild: "flutter build"),
        CleanupProjectRule("Gradle", folder: ".gradle", rootMarkers: gradle, lockfiles: gradle, rebuild: "./gradlew build"),
        CleanupProjectRule(
            "Gradle", folder: "build", rootMarkers: ["build.gradle", "build.gradle.kts"],
            lockfiles: ["build.gradle", "build.gradle.kts"], rebuild: "./gradlew build"),
        CleanupProjectRule(
            "CocoaPods", folder: "Pods", rootMarkers: ["Podfile"], lockfiles: ["Podfile.lock"], rebuild: "pod install"),
        CleanupProjectRule(
            "CocoaPods", folder: "ios/Pods", rootMarkers: ["ios/Podfile"], lockfiles: ["ios/Podfile.lock"],
            rebuild: "pod install"),
        CleanupProjectRule(
            "SwiftPM", folder: ".build", rootMarkers: ["Package.swift"], lockfiles: ["Package.resolved"],
            rebuild: "swift build"),
        CleanupProjectRule("Elixir", folder: "_build", rootMarkers: ["mix.exs"], lockfiles: ["mix.lock"], rebuild: "mix compile"),
        CleanupProjectRule("Elixir", folder: "deps", rootMarkers: ["mix.exs"], lockfiles: ["mix.lock"], rebuild: "mix deps.get"),
        CleanupProjectRule("Maven", folder: "target", rootMarkers: ["pom.xml"], lockfiles: ["pom.xml"], rebuild: "mvn package"),
        CleanupProjectRule("sbt", folder: "target", rootMarkers: ["build.sbt"], lockfiles: ["build.sbt"], rebuild: "sbt compile"),
        CleanupProjectRule(
            "sbt", folder: "project/target", rootMarkers: ["build.sbt"], lockfiles: ["build.sbt"], rebuild: "sbt compile"),
        CleanupProjectRule(
            ".NET", folder: "bin", extensions: ["csproj", "fsproj", "vbproj", "sln"], rebuild: "dotnet build",
            alwaysReview: true),
        CleanupProjectRule(
            ".NET", folder: "obj", extensions: ["csproj", "fsproj", "vbproj", "sln"], rebuild: "dotnet build"),
        CleanupProjectRule(
            "Composer", folder: "vendor", rootMarkers: ["composer.json"], lockfiles: ["composer.lock"],
            rebuild: "composer install"),
        CleanupProjectRule(
            "Bundler", folder: "vendor/bundle", rootMarkers: ["Gemfile"], lockfiles: ["Gemfile.lock"],
            rebuild: "bundle install"),
        CleanupProjectRule(
            "Stack", folder: ".stack-work", rootMarkers: ["stack.yaml"], lockfiles: ["stack.yaml.lock"],
            rebuild: "stack build"),
        CleanupProjectRule("Cabal", folder: "dist-newstyle", extensions: ["cabal"], rebuild: "cabal build"),
        CleanupProjectRule(
            "Zig", folder: ".zig-cache", rootMarkers: ["build.zig"], lockfiles: ["build.zig"], rebuild: "zig build"),
        CleanupProjectRule(
            "Zig", folder: "zig-cache", rootMarkers: ["build.zig"], lockfiles: ["build.zig"], rebuild: "zig build"),
        CleanupProjectRule("Zig", folder: "zig-out", rootMarkers: ["build.zig"], lockfiles: ["build.zig"], rebuild: "zig build"),
        CleanupProjectRule(
            "Dune", folder: "_build", rootMarkers: ["dune-project"], lockfiles: ["dune-project"], rebuild: "dune build"),
        CleanupProjectRule(
            "CMake", folder: "build", rootMarkers: ["CMakeLists.txt"], rebuild: "cmake --build", alwaysReview: true),
        // Holds the backend's state as well as downloaded providers; state refuses it outright.
        CleanupProjectRule(
            "Terraform", folder: ".terraform", extensions: ["tf"],
            refuseWhenPresent: ["terraform.tfstate", "terraform.tfstate.backup", "environment"],
            rebuild: "terraform init", alwaysReview: true),
        CleanupProjectRule(
            "Godot", folder: ".godot", rootMarkers: ["project.godot"], lockfiles: ["project.godot"],
            rebuild: "Opening the project in Godot"),
        // A reimport or shader rebuild can take half an hour on a large project.
        CleanupProjectRule(
            "Unity", folder: "Library", rootMarkers: ["ProjectSettings/ProjectVersion.txt"],
            rebuild: "Opening the project in Unity", alwaysReview: true),
        CleanupProjectRule(
            "Unity", folder: "Temp", rootMarkers: ["ProjectSettings/ProjectVersion.txt"],
            rebuild: "Opening the project in Unity", alwaysReview: true),
        CleanupProjectRule(
            "Unreal", folder: "Intermediate", extensions: ["uproject"], rebuild: "Building in Unreal",
            alwaysReview: true),
        CleanupProjectRule(
            "Unreal", folder: "DerivedDataCache", extensions: ["uproject"], rebuild: "Building in Unreal",
            alwaysReview: true)
    ]

    /// A folder tagged by its tool as a cache, per the CACHEDIR.TAG convention.
    static let cacheDirectoryTag = "CACHEDIR.TAG"
    static let cacheDirectorySignature = "Signature: 8a477f597d28d172789f06886806bc55"

    /// Folder names any rule can propose; the walk never descends into one looking for roots.
    static let artifactFolderNames: Set<String> = Set(rules.map(\.folderName))

    /// Dependency trees and tool caches, skipped wherever they sit when gauging activity.
    static let neverEditedFolderNames: Set<String> = [
        ".git", "node_modules", "venv", ".venv", "Pods", "DerivedDataCache", "dist-newstyle", "zig-cache",
        ".zig-cache", ".gradle", ".build", "target"
    ]

    /// The rules whose marker files sit at `root`, given its directory listing.
    static func rules(forRootListing names: Set<String>, exists: (String) -> Bool) -> [CleanupProjectRule] {
        let extensions = Set(names.map { ($0 as NSString).pathExtension.lowercased() })
        return rules.filter { rule in
            rule.rootMarkers.contains { $0.contains("/") ? exists($0) : names.contains($0) }
                || rule.rootMarkerExtensions.contains { extensions.contains($0) }
        }
    }
}
