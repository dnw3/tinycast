import Foundation

extension ProxyFailure {
    func message(in profile: ProxyProfile) -> String {
        switch self {
        case .coreMissing:
            String(localized: "This build has no proxy core. Download one in Settings › Proxy › General.")
        case .invalidProfile(let problems):
            problems.first.map { $0.message(in: profile) }
                ?? String(localized: "The proxy settings cannot be used as they are.")
        case .rejected(let reason):
            String(localized: "The proxy core refused the settings: \(reason)")
        case .storage(let reason):
            String(localized: "The proxy settings could not be written: \(reason)")
        case .unreachable:
            String(localized: "The proxy core did not respond.")
        case .coreExited(let status, _):
            String(localized: "The proxy core stopped unexpectedly (status \(status)).")
        case .sourceUpdate(let id, let reason?):
            String(
                localized:
                    "“\(profile.sources.first { $0.id == id }?.name ?? "")” could not be updated: \(reason)")
        case .sourceUpdate(let id, nil):
            String(localized: "“\(profile.sources.first { $0.id == id }?.name ?? "")” could not be updated.")
        case .ruleSetUpdate(let count, let reason):
            Self.ruleSetMessage(count: count, reason: reason)
        case .coreUpdate(let failure):
            failure.message
        case .coreDidNotStart(let tag):
            String(localized: "Core \(tag) did not start, so the previous core is running again.")
        case .helperUnavailable:
            String(localized: "The TUN helper is not responding. Install it again in Settings › Proxy.")
        case .helper(let failure):
            failure.message
        }
    }
}

extension ProxyFailure {
    private static func ruleSetMessage(count: Int, reason: String?) -> String {
        switch (count, reason) {
        case (1, let reason?): String(localized: "A rule set could not be updated: \(reason)")
        case (1, nil): String(localized: "A rule set could not be updated.")
        case (_, let reason?): String(localized: "\(count) rule sets could not be updated: \(reason)")
        case (_, nil): String(localized: "\(count) rule sets could not be updated.")
        }
    }
}

extension ProxyHelperFailure {
    var message: String {
        switch self {
        case .refused(let reason): String(localized: "The TUN helper refused the request: \(reason)")
        case .noCore: String(localized: "The TUN helper has no verified core to run.")
        case .digestMismatch: String(localized: "The core changed while it was handed to the TUN helper.")
        case .unsigned: String(localized: "The bundled core is not signed by this Tinycast.")
        case .notCore(let reported): String(localized: "The TUN helper could not run the core: \(reported)")
        case .storage(let reason): String(localized: "The TUN helper could not save its files: \(reason)")
        case .exited(let status, _):
            String(localized: "The proxy core stopped unexpectedly (status \(status)).")
        case .unreachable: String(localized: "The proxy core did not respond.")
        case .rejected(let reason): String(localized: "The proxy core refused the settings: \(reason)")
        }
    }
}

extension ProxyCoreUpdateFailure {
    var message: String {
        switch self {
        case .unreachable(let reason): String(localized: "GitHub could not be reached: \(reason)")
        case .rateLimited:
            String(localized: "GitHub is limiting requests from this network. Try again later.")
        case .noRelease: String(localized: "No stable mihomo release was found.")
        case .noAsset: String(localized: "The release has no build for this Mac.")
        case .unverifiable: String(localized: "The release publishes no checksum, so it was not installed.")
        case .checksumMismatch: String(localized: "The download does not match its published checksum.")
        case .damaged: String(localized: "The download is not a valid archive.")
        case .wrongIdentity(let reported):
            String(localized: "The downloaded core describes itself as “\(reported)”.")
        case .rejected(let reason): String(localized: "The new core refused the current settings: \(reason)")
        case .storage(let reason): String(localized: "The core could not be saved: \(reason)")
        }
    }
}

extension ProxyProblem {
    func message(in profile: ProxyProfile) -> String {
        String(localized: "\(subjectTitle(in: profile)): \(detail)")
    }

    private func subjectTitle(in profile: ProxyProfile) -> String {
        switch subject {
        case .general: return String(localized: "General")
        case .source(let id):
            return String(localized: "Source “\(profile.sources.first { $0.id == id }?.name ?? "")”")
        case .strategy(let id):
            return String(localized: "Strategy “\(profile.strategy(id)?.name ?? "")”")
        case .route(let id):
            let title = profile.routes.first { $0.id == id }?.title ?? id
            return String(localized: "Route “\(title)”")
        case .finalRoute: return ProxyRoute.finalTitle
        case .rule(let id):
            return String(localized: "Rule “\(profile.rules.first { $0.id == id }?.value ?? "")”")
        }
    }

    private var detail: String {
        switch kind {
        case .emptyName: String(localized: "needs a name")
        case .duplicateName: String(localized: "has the same name as another")
        case .reservedName: String(localized: "uses a name the core reserves")
        case .unsafeText: String(localized: "cannot contain a comma, #, &, = or a line break")
        case .missingStrategy: String(localized: "uses a strategy that no longer exists")
        case .memberCycle: String(localized: "includes itself through its members")
        case .noOptions: String(localized: "has nothing to choose from")
        case .invalidPattern(let pattern): String(localized: "has a pattern the core cannot read: \(pattern)")
        case .invalidValue: String(localized: "has a value that is not valid")
        case .invalidURL: String(localized: "needs an address starting with http:// or https://")
        case .invalidDNS: String(localized: "needs a domestic DNS server, with no spaces or commas")
        case .invalidPort: String(localized: "needs a mixed port from 1 to 65535")
        }
    }
}
