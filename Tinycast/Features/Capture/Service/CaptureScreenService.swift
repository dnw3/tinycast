import AppKit
import OSLog
import ScreenCaptureKit

@MainActor
enum CaptureScreenService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Capture")
    @MainActor struct Target {
        let display: SCDisplay
        let filter: SCContentFilter
        let windows: [SCWindow]
        let excludedPIDs: Set<pid_t>
        let screenFrame: CGRect
        let scale: CGFloat
    }

    static func target(screen: NSScreen, scrolling: Bool) async throws -> Target {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let displayID =
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure.displayChanged
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard content.applications.contains(where: { $0.processID == ownPID }) else {
            throw Failure.unavailable
        }
        let excluded = content.applications.filter {
            $0.processID == ownPID || scrolling && $0.bundleIdentifier == "com.apple.dock"
        }
        let excludedPIDs = Set(excluded.map(\.processID))
        let filter = SCContentFilter(
            display: display, excludingApplications: excluded,
            exceptingWindows: [])
        filter.includeMenuBar = true
        return Target(
            display: display, filter: filter,
            windows: content.windows.filter {
                $0.isOnScreen && !excludedPIDs.contains($0.owningApplication?.processID ?? 0)
                    && $0.windowLayer == 0
            },
            excludedPIDs: excludedPIDs,
            screenFrame: screen.frame, scale: CGFloat(filter.pointPixelScale))
    }

    static func image(
        target: Target, rect: CGRect? = nil, window: SCWindow? = nil, cursor: Bool, presentation: Bool = false
    ) async throws -> CGImage {
        try Task.checkCancellation()
        let filter = window.map { SCContentFilter(desktopIndependentWindow: $0) } ?? target.filter
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = cursor
        configuration.ignoreShadows = !presentation
        configuration.dynamicRange = .sdr
        configuration.displayIntent = presentation ? .local : .canonical
        let bounds = rect ?? filter.contentRect
        if let rect { configuration.sourceRect = rect }
        configuration.width = Int((bounds.width * CGFloat(filter.pointPixelScale)).rounded())
        configuration.height = Int((bounds.height * CGFloat(filter.pointPixelScale)).rounded())
        _ = try CapturePixelSize(width: configuration.width, height: configuration.height)
        let output = try await SCScreenshotManager.captureScreenshot(
            contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard let image = output.sdrImage else { throw Failure.unavailable }
        return image
    }

    static func window(at point: CGPoint, target: Target) -> SCWindow? {
        let quartz = CGPoint(x: point.x, y: (NSScreen.primary?.frame.maxY ?? 0) - point.y)
        let order =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in order {
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                let window = target.windows.first(where: { $0.windowID == number }),
                window.frame.contains(quartz)
            else { continue }
            return window
        }
        return nil
    }

    static func assessTarget(
        windowID: CGWindowID, pid: pid_t, frame: CGRect, region: CGRect, excludedPIDs: Set<pid_t>
    ) -> CaptureVisibilityPolicy.Assessment {
        let windows =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let snapshots = windows.compactMap { info -> CaptureVisibilityPolicy.Window? in
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                let values = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: values as CFDictionary),
                let owner = info[kCGWindowOwnerPID as String] as? Int32,
                let layer = info[kCGWindowLayer as String] as? Int
            else { return nil }
            return .init(
                id: number, pid: owner, frame: bounds, layer: layer,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let assessment = CaptureVisibilityPolicy.assess(
            windowID: windowID, pid: pid, frame: frame, region: region,
            excludedPIDs: excludedPIDs,
            frontmostPID: frontmost,
            cursorLayer: Int(CGWindowLevelForKey(.cursorWindow)), windows: snapshots)
        if assessment.status != .visible {
            let obstruction = assessment.obstructingWindow
            logger.notice(
                """
                Capture paused: \(assessment.status.rawValue, privacy: .public), target=\(windowID), pid=\(pid), \
                frontmost=\(frontmost ?? -1), obstruction=\(obstruction?.id ?? 0), \
                owner=\(obstruction?.pid ?? 0), layer=\(obstruction?.layer ?? -1)
                """)
        }
        return assessment
    }

    enum Failure: LocalizedError {
        case displayChanged, unavailable
        var errorDescription: String? {
            switch self {
            case .displayChanged: String(localized: "The display changed. Select a region again.")
            case .unavailable:
                String(
                    localized:
                        "The screen could not be captured. Check Screen Recording permission and retry.")
            }
        }
    }
}
