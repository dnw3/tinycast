import AppKit
@preconcurrency import ApplicationServices

@MainActor
struct TranslationTarget {
    let app: NSRunningApplication
    let element: AXUIElement
    let value: String
    let range: NSRange

    var title: String { range.length == 0 ? "Insert" : "Replace" }
    var selectedText: String? { TranslationTargetPolicy.selection(in: value, range: range) }

    static func capture(in app: NSRunningApplication) -> Self? {
        guard Permissions.isAccessibilityTrusted(),
            let element = AccessibilityText.focusedElement(in: app),
            let value = value(in: element), let range = range(in: element),
            Range(range, in: value) != nil,
            isEditable(element)
        else { return nil }
        return Self(app: app, element: element, value: value, range: range)
    }

    func isCurrent() -> Bool {
        guard !app.isTerminated, Permissions.isAccessibilityTrusted(),
            let focused = AccessibilityText.focusedElement(in: app), CFEqual(focused, element),
            Self.isEditable(focused),
            let current = Self.value(in: focused), let currentRange = Self.range(in: focused)
        else { return false }
        return TranslationTargetPolicy.matches(
            original: value, range: range, current: current, currentRange: currentRange)
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue
        else { return false }
        return true
    }

    private static func value(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func range(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
