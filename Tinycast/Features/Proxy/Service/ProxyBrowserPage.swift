import Foundation

/// The page open in the browser the user was in, read over Apple Events for a new rule.
enum ProxyBrowserPage {
    struct Browser: Sendable {
        let bundleID: String
        let name: String
        /// Safari names its front page a document; Chromium browsers name it a window's tab.
        let isSafari: Bool

        init?(bundleID: String?, name: String?) {
            guard let bundleID, let name else { return nil }
            switch bundleID {
            case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
                isSafari = true
            case "com.google.Chrome", "com.google.Chrome.beta", "com.microsoft.edgemac", "com.brave.Browser",
                "company.thebrowser.Browser", "com.vivaldi.Vivaldi":
                isSafari = false
            default:
                return nil
            }
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// The front page's address, or nil when the browser has none or automation is refused.
    @concurrent
    static func address(in browser: Browser) async -> String? {
        let page = browser.isSafari ? "URL of front document" : "URL of active tab of front window"
        let source = """
            with timeout of 2 seconds
                tell application id "\(browser.bundleID)" to return \(page)
            end timeout
            """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let address = result.stringValue, !address.isEmpty else { return nil }
        return address
    }
}
