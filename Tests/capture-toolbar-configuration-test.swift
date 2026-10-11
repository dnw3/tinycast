import Foundation
import CoreGraphics

@main
struct CaptureToolbarConfigurationTests {
    static func main() throws {
        let suite = "capture-toolbar-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let encoder = JSONEncoder()
        let old: Set<CaptureToolbarItem> = [.annotation(.pen), .scanCodes]
        let legacy = try encoder.encode(old)
        let upgraded = CaptureToolbarConfiguration(data: legacy)
        precondition(upgraded.items.intersection(old) == old)
        precondition(!upgraded.items.contains(.annotation(.arrow)))
        precondition(upgraded.items.contains(.annotation(.select)))
        precondition(upgraded.items.contains(.action(.scroll)))
        precondition(!upgraded.items.contains(.action(.record)))
        defaults.set(try encoder.encode(upgraded), forKey: "toolbar")
        precondition(CaptureToolbarConfiguration(data: defaults.data(forKey: "toolbar")).items == upgraded.items)
        let hiddenActions = CaptureToolbarConfiguration(items: old)
        defaults.set(try encoder.encode(hiddenActions), forKey: "toolbar")
        let reopened = CaptureToolbarConfiguration(data: defaults.data(forKey: "toolbar"))
        precondition(reopened.items == old.union([.annotation(.select)]))
        precondition(reopened.items.allSatisfy { !$0.isAction })
        precondition(CaptureToolbarConfiguration(data: nil).items == CaptureToolbarItem.standard)
        precondition(CaptureToolbarConfiguration(data: Data("broken".utf8)).items == CaptureToolbarItem.standard)
        precondition(CaptureToolbarConfiguration(data: Data(repeating: 0, count: 8193)).items == CaptureToolbarItem.standard)
        let all = Set(CaptureToolbarItem.all)
        let censor = CaptureToolbarConfiguration(items: [.annotation(.blur), .annotation(.erase)],
            order: [.annotation(.pen), .annotation(.erase), .annotation(.blur)])
        precondition(censor.items == [.annotation(.select), .annotation(.cover)])
        precondition(censor.order.prefix(3) == [.annotation(.select), .annotation(.pen), .annotation(.cover)])
        precondition(censor.order.filter { $0 == .annotation(.cover) }.count == 1)
        for query in ["blur", "马赛克", "text only", "M", "F", "E"] {
            precondition(CaptureToolbarItem.annotation(.cover).matches(query))
        }
        precondition(all.count == CaptureToolbarItem.all.count && CaptureToolbarItem.standard.isSubset(of: all))
        for action in CaptureToolbarAction.allCases {
            precondition(all.contains(.action(action)))
            precondition(!action.title.isEmpty && !action.symbol.isEmpty)
        }
        var ordered = CaptureToolbarConfiguration(items: all, order: [.action(.save), .annotation(.pen), .action(.copy)])
        precondition(ordered.order.first == .annotation(.select))
        precondition(ordered.orderedItems(actions: true).prefix(2) == [.action(.save), .action(.copy)])
        ordered.move(.action(.copy), by: -1)
        ordered.move(.annotation(.select), by: 1)
        precondition(ordered.orderedItems(actions: true).first == .action(.copy))
        precondition(ordered.order.first == .annotation(.select))
        let annotationOrder = ordered.orderedItems(actions: false, visibleOnly: false)
        let actionOrder = ordered.orderedItems(actions: true, visibleOnly: false)
        ordered.reorder(actions: true, from: IndexSet([0, 2]), to: actionOrder.count)
        precondition(ordered.orderedItems(actions: true, visibleOnly: false).suffix(2) == [actionOrder[0], actionOrder[2]])
        precondition(ordered.orderedItems(actions: false, visibleOnly: false) == annotationOrder)
        let afterDrag = ordered.order
        ordered.reorder(actions: false, from: IndexSet(integer: 1), to: 0)
        ordered.reorder(actions: false, from: IndexSet(integer: 0), to: annotationOrder.count)
        ordered.reorder(actions: true, from: IndexSet(integer: 500), to: 0)
        precondition(ordered.order == afterDrag)
        ordered.reorder(actions: false, from: IndexSet(integer: 1), to: annotationOrder.count)
        precondition(ordered.orderedItems(actions: false, visibleOnly: false).last == annotationOrder[1])
        precondition(ordered.order.first == .annotation(.select))
        let restored = CaptureToolbarConfiguration(data: try encoder.encode(ordered))
        precondition(restored.order == ordered.order && restored.items == ordered.items)
        let duplicates = CaptureToolbarConfiguration(items: all, order: Array(repeating: .annotation(.pen), count: 5))
        precondition(duplicates.order.count == all.count && Set(duplicates.order) == all)
        precondition(CaptureToolbarItem.action(.scroll).matches("滚动"))
        precondition(CaptureToolbarItem.annotation(.arrow).matches("A"))
        precondition(CaptureToolbarItem.action(.recognize).matches("ocr"))
        precondition(!CaptureToolbarItem.action(.copy).matches("滚动"))
        precondition(CaptureToolbarConfiguration.capacity(length: 680, cell: 30, spacing: 2, reserved: 5) == 16)
        for length in [0.0, 30, 100, 232, 680, 1024] {
            let capacity = CaptureToolbarConfiguration.capacity(length: length, cell: 30, spacing: 2, reserved: 5)
            precondition(capacity >= 0)
            if capacity > 0 { precondition(Double(capacity + 5) * 32 - 2 <= length) }
        }
        precondition(CaptureToolbarConfiguration.capacity(length: .nan, cell: 30, spacing: 2, reserved: 5) == 0)
        precondition(CaptureToolbarConfiguration.capacity(length: .greatestFiniteMagnitude,
            cell: 30, spacing: 2, reserved: 5) >= 0)
        print("Capture toolbar: legacy choices preserved, hidden actions survive reopening, complete action catalog")
    }
}
