import AppKit
import SwiftUI

/// Keeps a pill up while an agent waits on a reader who is not in the AI Chat window.
@MainActor
final class AgentWaitingHUDController {
    private unowned let coordinator: AIChatCoordinator
    private let settings: AppSettings
    private let presenter: HUDPresenter
    /// Waved away by the reader; the pill comes back only for a question not among these.
    private var dismissed: Set<String> = []
    /// What the pill on screen answers, so an unrelated change never rebuilds it.
    private var shown: String?
    private var observers: [NotificationToken] = []

    init(coordinator: AIChatCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        // No dwell: the pill leaves when the wait does.
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudWaitingEdgeOffset), dwell: 0,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            let observer = center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                // By the next turn the key window has settled, whichever one took over.
                Task { @MainActor in self?.refresh() }
            }
            observers.append(NotificationToken(observer, center: center))
        }
        observe()
    }

    /// Re-armed after every read; the hop is because `onChange` fires before the write lands.
    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        let waiting = coordinator.chats.waiting
        let questions = Set(waiting.compactMap { Self.question(in: $0) })
        if questions.isEmpty { dismissed = [] }
        guard let first = waiting.first, let request = first.pendingApproval,
            let question = Self.question(in: first), !coordinator.isWindowKey,
            !questions.isSubset(of: dismissed)
        else {
            hide()
            return
        }
        let identity = "\(question)#\(waiting.count)"
        guard identity != shown else { return }
        shown = identity
        let message: String
        if waiting.count > 1 {
            message = String(localized: "\(waiting.count) chats need your OK")
        } else if let agent = coordinator.agentKind(for: first)?.title {
            message = String(localized: "\(agent) needs your OK · \(request.title)")
        } else {
            message = request.title
        }
        let view = AgentWaitingHUDView(
            message: message,
            onView: { [weak self] in self?.coordinator.showWaiting(first) },
            onDismiss: { [weak self] in
                self?.dismissed.formUnion(questions)
                self?.hide()
            })
        presenter.show(
            view.environment(\.metrics, settings.interfaceSize.metrics), dwells: false,
            interactive: true)
    }

    private func hide() {
        guard shown != nil else { return }
        shown = nil
        presenter.dismiss()
    }

    /// A question is its chat's and its own: two chats may ask with the same call ID.
    private static func question(in chat: AIChatState) -> String? {
        chat.pendingApproval.map { "\(chat.session.id)/\($0.id)" }
    }
}
