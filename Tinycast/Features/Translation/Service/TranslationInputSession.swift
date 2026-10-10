import Foundation

@MainActor
final class TranslationInputSession {
    private let wait: () async throws -> Void
    private var pending: Task<Void, Never>?

    init(wait: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(800)) }) {
        self.wait = wait
    }

    isolated deinit { pending?.cancel() }

    func schedule(text: String, isComposing: Bool, action: @escaping () -> Void) {
        cancel()
        guard !isComposing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pending = Task { [wait] in
            do {
                try await wait()
                try Task.checkCancellation()
            } catch { return }
            action()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
