import Foundation

struct CaptureToolbarConfiguration: Codable, Sendable {
    var items: Set<CaptureToolbarItem>
    var order: [CaptureToolbarItem]

    init(items: Set<CaptureToolbarItem>, order: [CaptureToolbarItem] = []) {
        self.items = Set(items.map(\.toolbarEntry)).union([.annotation(.select)])
        var seen: Set<CaptureToolbarItem> = [.annotation(.select)]
        self.order = [.annotation(.select)] + (order + CaptureToolbarItem.all).map(\.toolbarEntry)
            .filter { seen.insert($0).inserted }
    }

    private enum CodingKeys: CodingKey { case items, order }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: try container.decode(Set<CaptureToolbarItem>.self, forKey: .items),
            order: try container.decodeIfPresent([CaptureToolbarItem].self, forKey: .order) ?? [])
    }

    init(data: Data?) {
        guard let data, data.count <= 8192 else {
            self.init(items: CaptureToolbarItem.standard)
            return
        }
        let decoder = JSONDecoder()
        if let configuration = try? decoder.decode(Self.self, from: data) {
            self = configuration
        } else if let items = try? decoder.decode(Set<CaptureToolbarItem>.self, from: data) {
            self.init(items: items.union(CaptureToolbarAction.standard.map(CaptureToolbarItem.action)))
        } else { self.init(items: CaptureToolbarItem.standard) }
    }

    func orderedItems(actions: Bool, visibleOnly: Bool = true) -> [CaptureToolbarItem] {
        order.filter { $0.isAction == actions && (!visibleOnly || items.contains($0)) }
    }

    mutating func move(_ item: CaptureToolbarItem, by offset: Int) {
        guard item != .annotation(.select), offset == -1 || offset == 1 else { return }
        let group = orderedItems(actions: item.isAction, visibleOnly: false)
        guard let index = group.firstIndex(of: item), group.indices.contains(index + offset),
            group[index + offset] != .annotation(.select),
            let source = order.firstIndex(of: item), let destination = order.firstIndex(of: group[index + offset])
        else { return }
        order.swapAt(source, destination)
    }

    mutating func reorder(actions: Bool, from offsets: IndexSet, to destination: Int) {
        var group = orderedItems(actions: actions, visibleOnly: false)
        guard !offsets.isEmpty, offsets.allSatisfy({ group.indices.contains($0) }),
            (0...group.count).contains(destination) else { return }
        let moved = offsets.map { group[$0] }
        for index in offsets.reversed() { group.remove(at: index) }
        group.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
        guard actions || group.first == .annotation(.select) else { return }
        var index = 0
        for slot in order.indices where order[slot].isAction == actions {
            order[slot] = group[index]
            index += 1
        }
    }

    static func capacity(length: Double, cell: Double, spacing: Double, reserved: Int) -> Int {
        guard length.isFinite, cell.isFinite, spacing.isFinite, cell > 0, spacing >= 0 else { return 0 }
        let count = Int(min(Double(CaptureToolbarItem.all.count), max(0, (length + spacing) / (cell + spacing))))
        return max(0, count - max(0, reserved))
    }
}
