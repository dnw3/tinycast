import SwiftUI

struct CaptureActionButton: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    let action: CaptureToolbarAction
    var inMenu = false

    private var available: Bool {
        !action.needsSelection
            || (coordinator.workspace != nil && coordinator.pendingCapture == nil
                && coordinator.workspace?.selectingTarget == false && coordinator.workspace?.displays == nil)
    }

    var body: some View {
        Group {
            if action == .save || action == .translate || action == .scroll {
                if inMenu {
                    Menu(LocalizedStringKey(action.title)) { alternatives }
                } else {
                    Menu {
                        alternatives
                    } label: {
                        CaptureToolbarGlyph(symbol: action.symbol)
                    } primaryAction: {
                        perform()
                    }
                    .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
                    .accessibilityLabel(Text(LocalizedStringKey(action.title))).tooltip(help)
                }
            } else if inMenu {
                Button(action: perform) {
                    Label {
                        Text(LocalizedStringKey(action.title))
                    } icon: {
                        CaptureToolbarGlyph(symbol: action.symbol)
                    }
                }
            } else {
                CaptureIconButton(
                    title: Bundle.main.localizedString(forKey: action.title, value: nil, table: nil),
                    symbol: action.symbol,
                    shortcut: action == .copy ? "⌘C / Return" : "", selected: action == .copy, action: perform
                )
                .contextMenu {
                    Button("Move to All Tools") {
                        coordinator.settings.setToolbarItem(.action(action), visible: false)
                    }
                    Menu("Customize Toolbar") { CaptureToolbarCustomization() }
                }
            }
        }
        .disabled(!available || coordinator.editor?.busy == true || coordinator.workspace?.busy == true)
    }

    private var help: String {
        action == .save
            ? String(localized: "Save As…  ⇧⌘S\nQuick Save  ⌘S")
            : Bundle.main.localizedString(forKey: action.title, value: nil, table: nil)
    }

    @ViewBuilder private var alternatives: some View {
        if action == .save {
            Button("Save As…") { coordinator.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Quick Save") { coordinator.save() }.keyboardShortcut("s", modifiers: .command)
            Button("Show Quick Save Folder") { coordinator.revealQuickSaveFolder() }
        } else if action == .scroll {
            Button("Vertical") { coordinator.beginScrollCapture(axis: .vertical) }
            Button("Horizontal") { coordinator.beginScrollCapture(axis: .horizontal) }
            Button("Adjust Region…") { coordinator.setCaptureMode(.scrolling) }
        } else {
            Button("Text Panel") { coordinator.recognize(translate: true) }
            Button("Translate in Image…") { coordinator.prepareImageTranslation() }
        }
    }

    private func perform() {
        guard available, coordinator.editor?.busy != true, coordinator.workspace?.busy != true else { return }
        switch action {
        case .copy: coordinator.copy()
        case .save: coordinator.saveAs()
        case .scroll: coordinator.beginScrollCapture()
        case .record: coordinator.setCaptureMode(.recording)
        case .pin: coordinator.pin()
        case .recognize: coordinator.recognize(translate: false)
        case .translate: coordinator.recognize(translate: true)
        case .share: coordinator.shareImage()
        case .upload:
            if coordinator.settings.uploadDestination != nil {
                coordinator.uploadCapture()
            } else {
                coordinator.showUploadSettings()
            }
        }
    }
}
