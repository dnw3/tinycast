import Foundation

enum CaptureVisibilityPolicy {
    enum Status: String, Sendable {
        case visible, inactive, excluded, missing, moved, outside, obscured
    }

    struct Assessment: Sendable {
        let status: Status
        var obstructingWindow: Window?
    }

    struct Window: Sendable {
        let id: UInt32
        let pid: Int32
        let frame: CGRect
        let layer: Int
        var alpha: Double = 1
    }

    /// `includedWindowIDs` are an excluded app's windows taken like any other's: Tinycast's own.
    static func assess(
        windowID: UInt32, pid: Int32, frame: CGRect, region: CGRect,
        excludedPIDs: Set<Int32>, includedWindowIDs: Set<UInt32> = [], frontmostPID: Int32?,
        cursorLayer: Int, windows: [Window]
    ) -> Assessment {
        let counts = { (id: UInt32, pid: Int32) in !excludedPIDs.contains(pid) || includedWindowIDs.contains(id) }
        guard frontmostPID == pid else { return Assessment(status: .inactive) }
        guard counts(windowID, pid) else { return Assessment(status: .excluded) }
        for window in windows {
            guard window.alpha > 0, window.layer < cursorLayer else { continue }
            if window.id == windowID {
                guard window.pid == pid else { return Assessment(status: .missing) }
                guard window.frame == frame else { return Assessment(status: .moved) }
                return Assessment(status: window.frame.contains(region) ? .visible : .outside)
            }
            if counts(window.id, window.pid), window.layer >= 0, window.frame.intersects(region) {
                return Assessment(status: .obscured, obstructingWindow: window)
            }
        }
        return Assessment(status: .missing)
    }
}
