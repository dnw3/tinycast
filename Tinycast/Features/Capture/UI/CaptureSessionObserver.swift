import AppKit

@MainActor
final class CaptureSessionObserver {
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private var tokens: [NotificationToken] = []
    private let interrupt: (String) -> Void

    init(
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        application: NotificationCenter = .default,
        distributed: NotificationCenter = DistributedNotificationCenter.default(),
        interrupt: @escaping (String) -> Void
    ) {
        self.interrupt = interrupt
        let events: [(NotificationCenter, Notification.Name, String)] = [
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "Session inactive"),
            (workspace, NSWorkspace.screensDidSleepNotification, "Display sleeping"),
            (workspace, NSWorkspace.willSleepNotification, "System sleeping"),
            (application, NSApplication.didChangeScreenParametersNotification, "Display changed"),
            (distributed, Self.screenLocked, "Screen locked")
        ]
        for (center, name, reason) in events {
            tokens.append(
                NotificationToken(
                    center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.interrupt(reason) }
                    }, center: center))
        }
    }
}
