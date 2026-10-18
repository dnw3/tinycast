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
                    shortcut: action == .copy ? "⌘C · ↵" : "", selected: action == .copy, action: perform
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

extension View {
    func captureBar(_ metrics: InterfaceMetrics) -> some View {
        padding(metrics.spacing.xs)
            .background { CaptureChrome.barShape(metrics).fill(.clear).frosted(in: CaptureChrome.barShape(metrics)) }
    }

    func captureCard(_ metrics: InterfaceMetrics) -> some View {
        padding(metrics.spacing.xs).captureGlass(metrics)
    }

    /// Scrim under the glass keeps contrast steady over whatever the screen shows.
    func captureGlass(_ metrics: InterfaceMetrics) -> some View {
        background(Theme.Colors.panelScrim).background(GlassEffectView())
            .clipShape(CaptureChrome.barShape(metrics))
    }

    /// A capture window's glass runs up under its transparent title bar.
    func captureWindowSurface() -> some View {
        background(Theme.Colors.panelScrim).background { GlassEffectView().ignoresSafeArea() }
    }

    /// A compact field sized for the tool bars, in the form field's fill and border.
    func captureField(_ metrics: InterfaceMetrics) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, metrics.spacing.sm).padding(.vertical, metrics.spacing.xxs)
            .background(Theme.Colors.cardFill, in: CaptureChrome.toolShape(metrics))
            .overlay { CaptureChrome.toolShape(metrics).strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline) }
    }

    /// Notes sit over arbitrary screenshots, so they take the HUD's scrim and glass for contrast.
    func captureNotice(_ metrics: InterfaceMetrics) -> some View {
        font(metrics.typography.bar)
            .padding(.horizontal, metrics.spacing.md).padding(.vertical, metrics.spacing.sm)
            .background(Theme.Colors.panelScrim).background(GlassEffectView())
            .clipShape(Capsule())
    }
}
