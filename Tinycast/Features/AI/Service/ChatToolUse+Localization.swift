import Foundation

extension ChatToolUse {
    var label: String {
        if state == .running {
            return origin.isEmpty ? String(localized: "Calling \(title)")
                : String(localized: "Calling \(origin) · \(title)")
        }
        return origin.isEmpty ? String(localized: "Called \(title)")
            : String(localized: "Called \(origin) · \(title)")
    }
}

extension Array where Element == ChatToolUse {
    var completedLabel: String {
        let label = String(localized: "Called \(count) tools")
        return failedCount == 0 ? label : String(localized: "\(label) · \(failedCount) failed")
    }
}
