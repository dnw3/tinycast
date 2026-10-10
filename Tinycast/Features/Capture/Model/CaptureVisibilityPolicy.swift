import Foundation

enum CaptureVisibilityPolicy {
    enum Status: String, Sendable {
        case visible, inactive, excluded, missing, moved, outside, obscured

        var message: String {
            switch self {
            case .visible: "Scroll inside the selected region"
            case .inactive: "Bring the captured window to the front, then choose Continue"
            case .excluded, .missing: "The captured window is unavailable. Select a region again"
            case .moved: "The captured window moved. Move it back, or select a region again"
            case .outside: "Select a region entirely inside the captured window"
            case .obscured: "Another window covers the capture region. Move it away, then choose Continue"
            }
        }
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

    static func assess(
        windowID: UInt32, pid: Int32, frame: CGRect, region: CGRect,
        excludedPIDs: Set<Int32>, frontmostPID: Int32?, cursorLayer: Int, windows: [Window]
    ) -> Assessment {
        guard frontmostPID == pid else { return Assessment(status: .inactive) }
        guard !excludedPIDs.contains(pid) else { return Assessment(status: .excluded) }
        for window in windows {
            guard window.alpha > 0, window.layer < cursorLayer else { continue }
            if window.id == windowID {
                guard window.pid == pid else { return Assessment(status: .missing) }
                guard window.frame == frame else { return Assessment(status: .moved) }
                return Assessment(status: window.frame.contains(region) ? .visible : .outside)
            }
            if !excludedPIDs.contains(window.pid), window.layer >= 0, window.frame.intersects(region) {
                return Assessment(status: .obscured, obstructingWindow: window)
            }
        }
        return Assessment(status: .missing)
    }
}
