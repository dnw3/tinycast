import AppKit
// AX attribute keys are C globals accessed only on the main actor.
@preconcurrency import ApplicationServices

@MainActor
enum TranslationSelectionReader {
    static func copyAction(in app: NSRunningApplication) -> (@MainActor () -> Bool)? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        guard let bar = attribute(application, kAXMenuBarAttribute),
            CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return nil }
        let deadline = ContinuousClock.now + .seconds(1)
        guard let item = copyItem(in: unsafeDowncast(bar, to: AXUIElement.self), depth: 0, deadline: deadline)
        else { return nil }
        return {
            guard !app.isTerminated, !Task.isCancelled,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                attribute(item, kAXEnabledAttribute) as? Bool == true
            else { return false }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
    }

    private static func copyItem(
        in element: AXUIElement, depth: Int, deadline: ContinuousClock.Instant
    ) -> AXUIElement? {
        guard depth < 6, ContinuousClock.now < deadline else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.2)
        if (attribute(element, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "c",
            (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0,
            attribute(element, kAXEnabledAttribute) as? Bool == true
        { return element }
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children {
            if let item = copyItem(in: child, depth: depth + 1, deadline: deadline) { return item }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
