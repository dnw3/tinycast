import SwiftUI

struct CaptureToolbarCustomization: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        Menu("Annotation Toolbar") {
            ForEach(CaptureToolbarItem.all.filter { !$0.isAction }, id: \.self) { item in toggle(item) }
        }
        Menu("Action Toolbar") {
            ForEach(CaptureToolbarAction.allCases, id: \.self) { action in toggle(.action(action)) }
        }
        Button("Arrange and Search…") { coordinator.toolbarCustomization.show(coordinator) }
        Divider()
        Button("Reset Toolbar") { coordinator.settings.resetToolbar() }
    }

    private func toggle(_ item: CaptureToolbarItem) -> some View {
        Toggle(LocalizedStringKey(item.title), isOn: Binding(
            get: { coordinator.settings.toolbarItems.contains(item) },
            set: { coordinator.settings.setToolbarItem(item, visible: $0) }))
            .disabled(item == .annotation(.select))
    }
}
