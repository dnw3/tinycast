import Foundation

/// Finds iCloud Drive files whose local copy can go while the file stays in iCloud.
nonisolated enum CleanupCloudScanner {
    static let entryBudget = 200_000
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey, .totalFileAllocatedSizeKey
    ]

    static func discover(_ environment: CleanupScanner.Environment) -> [CleanupItem] {
        let root = environment.home + "/" + CleanupCloudPolicy.root
        guard environment.hasFullDiskAccess,
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var items: [CleanupItem] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            guard visited <= entryBudget, !Task.isCancelled else { break }
            let path = url.standardizedFileURL.path
            guard !CleanupExclusions.contains(path, in: environment.exclusions),
                let evidence = evidence(url), CleanupCloudPolicy.qualifies(evidence)
            else { continue }
            var context = CleanupScanner.context(for: path, environment: environment)
            context.evidence = .cloud(evidence)
            guard case .allowed(let match) = CleanupSafetyPolicy.evaluate(
                path: path, expected: .iCloudDownloads, context: context)
            else { continue }
            var item = CleanupItem(
                path: path, match: match, name: url.lastPathComponent, modified: nil, protection: .removable)
            item.size = evidence.bytes
            items.append(item)
        }
        return items
    }

    /// The runner's fresh read for one path.
    static func evidence(for path: String) -> CleanupCloudEvidence? {
        evidence(URL(fileURLWithPath: path))
    }

    private static func evidence(_ url: URL) -> CleanupCloudEvidence? {
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
        return CleanupCloudEvidence(
            isUbiquitous: values.isUbiquitousItem ?? false,
            isCurrent: values.ubiquitousItemDownloadingStatus == .current,
            isUploaded: values.ubiquitousItemIsUploaded ?? false,
            isUploading: values.ubiquitousItemIsUploading ?? false,
            hasConflicts: values.ubiquitousItemHasUnresolvedConflicts ?? false,
            bytes: Int64(values.totalFileAllocatedSize ?? 0))
    }
}
