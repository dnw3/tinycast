import Foundation
@preconcurrency import ApplicationServices

enum CaptureElementAccess {
    nonisolated static func frame(pid: pid_t, at point: CGPoint) throws -> CGRect? {
        try Task.checkCancellation()
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &element) == .success
        else { return nil }
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard let current = element else { return nil }
            AXUIElementSetMessagingTimeout(current, 0.2)
            if let position = value(current, kAXPositionAttribute), let size = value(current, kAXSizeAttribute),
                CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
            {
                // swiftlint:disable:next force_cast
                let position = position as! AXValue, size = size as! AXValue
                var origin = CGPoint.zero, dimensions = CGSize.zero
                if AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) {
                    let rect = CGRect(origin: origin, size: dimensions)
                    if CaptureGeometry.valid(rect), rect.contains(point) { return rect }
                }
            }
            guard let parent = value(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            // swiftlint:disable:next force_cast
            element = (parent as! AXUIElement)
        }
        return nil
    }

    nonisolated private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
}
