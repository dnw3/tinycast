import Foundation

extension CaptureVisibilityPolicy.Status {
    var message: String {
        switch self {
        case .visible: String(localized: "Scroll inside the selected region")
        case .inactive: String(localized: "Bring the captured window to the front, then choose Continue")
        case .excluded, .missing: String(localized: "The captured window is unavailable. Select a region again")
        case .moved: String(localized: "The captured window moved. Move it back, or select a region again")
        case .outside: String(localized: "Select a region entirely inside the captured window")
        case .obscured:
            String(localized: "Another window covers the capture region. Move it away, then choose Continue")
        }
    }
}
