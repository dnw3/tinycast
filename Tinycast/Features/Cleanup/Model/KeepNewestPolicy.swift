import Foundation

/// Picks the oldest version-named siblings to offer; Xcode re-copies a device's symbols on demand.
enum KeepNewestPolicy {
    /// Everything beyond the newest `keep`; a name with no readable version is always kept.
    static func removable(_ names: [String], keep: Int) -> Set<String> {
        let versioned = names.compactMap { name in version(in: name).map { (name, $0) } }
        let newestFirst = versioned.sorted { lhs, rhs in
            let order = compare(lhs.1, rhs.1)
            return order == .orderedSame ? lhs.0 > rhs.0 : order == .orderedDescending
        }
        return Set(newestFirst.dropFirst(keep).map(\.0))
    }

    /// The first dotted number: 17.5.1 in "17.5.1 (21F90) arm64e", 17.0 in "iPhone15,2 17.0".
    static func version(in name: String) -> [Int]? {
        for token in name.split(separator: " ") {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let numbers = parts.compactMap { Int($0) }
            if numbers.count == parts.count { return numbers }
        }
        return nil
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
