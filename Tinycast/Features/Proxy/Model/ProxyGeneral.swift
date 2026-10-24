import Foundation

/// How the proxy connects and resolves names, independent of what traffic goes where.
struct ProxyGeneral: Codable, Equatable, Sendable {
    enum DNSMode: String, Codable, CaseIterable, Sendable {
        case fakeIP = "fake-ip"
        case realIP = "redir-host"
    }

    var usesTUN = true
    /// A LAN DNS server bypasses the TUN device, so a public one stands in while connected.
    var placeholderDNS = true
    var connectsAtLogin = true
    var staysConnectedAfterQuit = true
    var dnsMode = DNSMode.fakeIP
    var domesticDNS = ["223.5.5.5", "119.29.29.29"]
    /// Reached through the default strategy, for the domains the foreign route lists.
    var foreignDNS = ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"]
    var mixedPort = 7897
    var allowsLAN = false
    /// Seconds between subscription updates; zero updates only on request.
    var subscriptionUpdateInterval = 43_200
    var updatesSubscriptionsThroughProxy = false
    var showsMenuBarItem = false
    /// Upload and download rates beside the menu bar icon, read once a second while connected.
    var showsMenuBarSpeed = false

    init() {}

    /// A key an older file lacks keeps its default, so adding a setting never loses the rest.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProxyGeneral()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        usesTUN = try value(.usesTUN, defaults.usesTUN)
        placeholderDNS = try value(.placeholderDNS, defaults.placeholderDNS)
        connectsAtLogin = try value(.connectsAtLogin, defaults.connectsAtLogin)
        staysConnectedAfterQuit = try value(.staysConnectedAfterQuit, defaults.staysConnectedAfterQuit)
        dnsMode = try value(.dnsMode, defaults.dnsMode)
        domesticDNS = try value(.domesticDNS, defaults.domesticDNS)
        foreignDNS = try value(.foreignDNS, defaults.foreignDNS)
        mixedPort = try value(.mixedPort, defaults.mixedPort)
        allowsLAN = try value(.allowsLAN, defaults.allowsLAN)
        subscriptionUpdateInterval = try value(
            .subscriptionUpdateInterval, defaults.subscriptionUpdateInterval)
        updatesSubscriptionsThroughProxy = try value(
            .updatesSubscriptionsThroughProxy, defaults.updatesSubscriptionsThroughProxy)
        showsMenuBarItem = try value(.showsMenuBarItem, defaults.showsMenuBarItem)
        showsMenuBarSpeed = try value(.showsMenuBarSpeed, defaults.showsMenuBarSpeed)
    }
}
