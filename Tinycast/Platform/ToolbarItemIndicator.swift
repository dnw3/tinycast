// `@preconcurrency`: the SDK declares `NSItemBadge.indicator` a mutable static, not a constant.
@preconcurrency import AppKit

extension NSToolbarItem {
    /// The system's indicator dot, kept to this file so no other file needs the import above.
    var showsIndicator: Bool {
        get { badge == .indicator }
        set { badge = newValue ? .indicator : nil }
    }
}
