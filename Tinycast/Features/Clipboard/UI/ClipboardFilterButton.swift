import SwiftUI

struct ClipboardFilterButton: View {
    let filter: ClipboardFilter
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: Bundle.main.localizedString(forKey: filter.title, value: nil, table: nil),
            systemImage: filter.systemImage,
            isOpen: isOpen,
            help: String(localized: "Filter by type  ⌘P"),
            action: action)
    }
}
