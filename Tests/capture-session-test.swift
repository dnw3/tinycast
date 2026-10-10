import AppKit

@main
@MainActor
struct CaptureSessionTests {
    static func main() async {
        let workspace = NotificationCenter(), application = NotificationCenter(), distributed = NotificationCenter()
        let (events, continuation) = AsyncStream<String>.makeStream()
        var received: [String] = []
        var observer: CaptureSessionObserver? = CaptureSessionObserver(
            workspace: workspace, application: application, distributed: distributed
        ) { reason in
            received.append(reason)
            continuation.yield(reason)
        }
        weak var lifetime = observer
        var iterator = events.makeAsyncIterator()
        application.post(name: CaptureSessionObserver.screenLocked, object: nil)
        let cases: [(NotificationCenter, Notification.Name, String)] = [
            (distributed, CaptureSessionObserver.screenLocked, "Screen locked"),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "Session inactive"),
            (workspace, NSWorkspace.screensDidSleepNotification, "Display sleeping"),
            (workspace, NSWorkspace.willSleepNotification, "System sleeping"),
            (application, NSApplication.didChangeScreenParametersNotification, "Display changed")
        ]
        for (center, name, reason) in cases {
            center.post(name: name, object: nil)
            let delivered = await iterator.next()
            precondition(delivered == reason)
        }
        precondition(received.count == cases.count)
        distributed.post(name: CaptureSessionObserver.screenLocked, object: nil)
        observer = nil
        precondition(lifetime == nil)
        continuation.finish()
        let finished = await iterator.next()
        precondition(finished == nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        await Task.yield()
        precondition(received.count == cases.count, "a stopped observer delivered a stale interruption")
        print("Capture lock, sleep, session and display interruption routing and observer release passed")
    }
}
