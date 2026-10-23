import SwiftUI

/// Tinycast's own menu-bar item: no feature can hide it, and only a waiting agent marks it.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        if AppCore.shared.aiChats.waiting.isEmpty {
            Image("MenuBarIcon")
                .accessibilityLabel(appName)
        } else {
            HStack(spacing: Theme.Spacing.xs) {
                Image("MenuBarIcon")
                Image(nsImage: waitingDot)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(appName): an agent is waiting for you"))
        }
    }

    /// Not a template, so the status bar keeps it blue rather than ink it like the icon.
    private var waitingDot: NSImage {
        let size = NSSize(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(Theme.Colors.waiting).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct MenuBarMenu: View {
    let appName: String

    var body: some View {
        Button("Open \(appName)") {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        // Read through Observation, so switching the feature off takes the row with it.
        if AppCore.shared.settings.clipboardEnabled {
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
        }
        if let available = AppCore.shared.cleanupSchedule.lowSpaceAvailable {
            Button("Free Up Space… \(available.formatted(.byteCount(style: .file))) left") {
                AppCore.shared.cleanupCoordinator.show()
            }
        }
        if AppCore.shared.captureCoordinator.recording != nil {
            Button("Stop Recording") { AppCore.shared.captureCoordinator.finishRecording() }
        }
        ForEach(AppCore.shared.aiChats.waiting, id: \.session.id) { chat in
            let coordinator = AppCore.shared.aiChatCoordinator
            Button("Review Request in “\(coordinator.title(of: chat))”…") {
                coordinator.showWaiting(chat)
            }
        }
        Divider()
        Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        Button("Support \(appName)…") { AppCore.shared.supportCoordinator.showSupport() }
        Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
        Button("Quit \(appName)") { NSApp.terminate(nil) }
    }
}
