import Foundation

/// What the helper keeps across restarts: the core Tinycast wants and what running it changed.
struct ProxyHelperRecord: Codable, Equatable, Sendable {
    /// The installed copy as the helper verified it, checked again before every start.
    struct Core: Codable, Equatable, Sendable {
        var sha256: String
        var tag: String
    }

    var wantsCore = false
    var outlivesClient = false
    var placeholderDNS = false
    /// `kern.bootsessionuuid` when the core was asked for; a new boot never resumes it unasked.
    var boot: String?
    var dns: ProxyDNSBackup?
    var core: Core?

    init() {}

    /// A key an older helper did not write keeps its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wantsCore = try container.decodeIfPresent(Bool.self, forKey: .wantsCore) ?? false
        outlivesClient = try container.decodeIfPresent(Bool.self, forKey: .outlivesClient) ?? false
        placeholderDNS = try container.decodeIfPresent(Bool.self, forKey: .placeholderDNS) ?? false
        boot = try container.decodeIfPresent(String.self, forKey: .boot)
        dns = try container.decodeIfPresent(ProxyDNSBackup.self, forKey: .dns)
        core = try container.decodeIfPresent(Core.self, forKey: .core)
    }

    struct LaunchPlan: Equatable, Sendable {
        var resumesCore = false
        var restoresDNS = false
    }

    /// What a freshly started helper does unasked: resume after a crash, or tidy up.
    mutating func plan(forLaunchIn boot: String) -> LaunchPlan {
        if wantsCore, self.boot == boot { return LaunchPlan(resumesCore: true) }
        wantsCore = false
        return LaunchPlan(restoresDNS: dns != nil)
    }
}
