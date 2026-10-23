import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    enum State: String, Equatable, Sendable {
        case streaming
        case complete
        case failed
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State
    let sentAt: Date
    let images: [AIImage]
    /// Sent PDFs; a text file is not one, its contents reached the model as text.
    let documents: [AIDocument]
    /// Web searches the reply made, in order; each sits in the text where it happened.
    var searches: [ChatSearch]
    /// Tools the reply called, pinned the same way; the calls themselves never enter the context.
    var toolUses: [ChatToolUse]
    /// What the model shared of its thinking, a block per stretch of it, each where it happened.
    var reasoning: [ChatReasoning]
    /// What the route reported for this reply; the context card reads the latest one.
    var usage: AIUsage?
    /// The server a question was addressed to with `@server`; the text is stored without it.
    let toolScope: String?

    init(
        id: UUID = UUID(), role: Role, text: String, state: State = .complete,
        sentAt: Date = Date(), images: [AIImage] = [], documents: [AIDocument] = [],
        searches: [ChatSearch] = [],
        toolUses: [ChatToolUse] = [], reasoning: [ChatReasoning] = [], usage: AIUsage? = nil,
        toolScope: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.sentAt = sentAt
        self.images = images
        self.documents = documents
        self.searches = searches
        self.toolUses = toolUses
        self.reasoning = reasoning
        self.usage = usage
        self.toolScope = toolScope
    }

    /// Text still arrives only into the last of a streaming reply's `count` segments.
    func isArriving(segmentAt offset: Int, of count: Int) -> Bool {
        state == .streaming && offset == count - 1
    }

    /// A running step, or a thought or search still arriving, already shows the reply at work.
    var tailShowsProgress: Bool {
        switch segments.last {
        case .tools(let uses): uses.isLive
        case .reasoning(let block): block.duration == nil
        case .search(let search): !search.isComplete
        case .text, nil: false
        }
    }

    /// The next search or call's place among the reply's: with no text between, offsets tie.
    var nextSequence: Int { searches.count + toolUses.count }

    var reasoningText: String {
        reasoning.map(\.text).joined(separator: "\n\n")
    }

    /// The reply split around what it did: thinking, search or tool, text… each where it happened.
    var segments: [ChatSegment] {
        // At one offset, thinking came first: a model thinks, then searches or calls.
        let interruptions =
            (reasoning.map {
                (offset: $0.textOffset, sequence: -1, segment: ChatSegment.reasoning($0))
            }
            + searches.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.search($0))
            }
            + toolUses.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.tools([$0]))
            })
            .sorted { ($0.offset, $0.sequence) < ($1.offset, $1.sequence) }
        var segments: [ChatSegment] = []
        var rest = Substring(text)
        var consumed = 0
        for interruption in interruptions {
            let take = max(0, min(interruption.offset - consumed, rest.count))
            if take > 0 { segments.append(.text(String(rest.prefix(take)))) }
            if case .tools(let uses) = interruption.segment,
                case .tools(let previous) = segments.last
            {
                segments[segments.count - 1] = .tools(previous + uses)
            } else {
                segments.append(interruption.segment)
            }
            rest = rest.dropFirst(take)
            consumed += take
        }
        if !rest.isEmpty { segments.append(.text(String(rest))) }
        return segments
    }
}

struct ChatSearch: Equatable, Hashable, Sendable {
    var query: String?
    var isComplete: Bool
    /// Characters of reply text that had arrived when the search began.
    let textOffset: Int
    let sequence: Int
}

/// One tool call inside a reply: live while it runs, a record of what ran once it is done.
struct ChatToolUse: Equatable, Hashable, Sendable {
    enum State: String, Equatable, Hashable, Sendable {
        case running
        case completed
        case failed
        /// The reader refused it, so it never ran: neither done nor a failure.
        case declined
    }

    /// What an agent's own tool did; an MCP call has none and is named by its server instead.
    enum Kind: String, Equatable, Hashable, Sendable {
        case read
        case search
        case edit
        case command
        case other
    }

    let callID: String
    let origin: String
    let title: String
    var state: State
    /// Characters of reply text that had arrived when the call started.
    let textOffset: Int
    let sequence: Int
    var kind: Kind?
    /// The whole of what the step was given and what it gave back; a row saved before has none.
    var detail: ChatToolDetail?

    var label: String {
        if let kind {
            return Self.label(kind, title: title, state: state, exitCode: detail?.exitCode)
        }
        let target = origin.isEmpty ? title : "\(origin) · \(title)"
        return state == .running
            ? String(localized: "Calling \(target)") : String(localized: "Called \(target)")
    }

    /// While its approval card is up: the step has not started, whatever its row's state says.
    var awaitingLabel: String {
        switch kind {
        case .read?: String(localized: "Waiting to read \(title)")
        case .search?: String(localized: "Waiting to search \(title)")
        case .edit?: String(localized: "Waiting to edit \(title)")
        case .command?: String(localized: "Waiting to run \(title)")
        case .other?: String(localized: "Waiting to use \(title)")
        case nil: label
        }
    }

    private static func label(_ kind: Kind, title: String, state: State, exitCode: Int?) -> String {
        switch state {
        case .running:
            return switch kind {
            case .read: String(localized: "Reading \(title)")
            case .search: String(localized: "Searching \(title)")
            case .edit: String(localized: "Editing \(title)")
            case .command: String(localized: "Running \(title)")
            case .other: String(localized: "Using \(title)")
            }
        case .declined:
            return switch kind {
            case .read: String(localized: "Didn't read \(title)")
            case .search: String(localized: "Didn't search \(title)")
            case .edit: String(localized: "Didn't edit \(title)")
            case .command: String(localized: "Didn't run \(title)")
            case .other: String(localized: "Didn't use \(title)")
            }
        case .completed:
            return switch kind {
            case .read: String(localized: "Read \(title)")
            case .search: String(localized: "Searched \(title)")
            case .edit: String(localized: "Edited \(title)")
            case .command: String(localized: "Ran \(title)")
            case .other: String(localized: "Used \(title)")
            }
        // A command that exited non-zero did run; the number is what went wrong.
        case .failed where kind == .command && exitCode.map { $0 != 0 } == true:
            return String(localized: "Ran \(title) · exit code \(exitCode ?? 0)")
        case .failed:
            return switch kind {
            case .read: String(localized: "Couldn't read \(title)")
            case .search: String(localized: "Couldn't search \(title)")
            case .edit: String(localized: "Couldn't edit \(title)")
            case .command: String(localized: "Couldn't run \(title)")
            case .other: String(localized: "Couldn't use \(title)")
            }
        }
    }
}

extension Array where Element == ChatToolUse {
    var runningCall: ChatToolUse? { last { $0.state == .running } }
    var isLive: Bool { runningCall != nil }
    var failedCount: Int { count { $0.state == .failed } }
    var declinedCount: Int { count { $0.state == .declined } }

    /// What ran, by kind, then what failed and what the reader refused, which never ran at all.
    var completedLabel: String {
        let failures = failedCount
        let label: String
        if allSatisfy({ $0.kind != nil }) {
            let ran = filter { $0.state != .declined }.agentSummary
            label = failures == 0 ? ran : String(localized: "\(ran) · \(failures) failed")
        } else if failures == 0 {
            label = String(localized: "Called \(count) tools")
        } else {
            label = String(localized: "Called \(count) tools · \(failures) failed")
        }
        guard declinedCount > 0 else { return label }
        let refused = String(localized: "\(declinedCount) not allowed")
        return label.isEmpty ? refused : String(localized: "\(label) · \(refused)")
    }

    /// One clause per kind of step, in the order an agent usually takes them.
    private var agentSummary: String {
        let tally = { (kind: ChatToolUse.Kind) in self.count { $0.kind == kind } }
        let clauses: [(ChatToolUse.Kind, (Int) -> AttributedString)] = [
            (.read, { AttributedString(localized: "read ^[\($0) file](inflect: true)") }),
            (.search, { AttributedString(localized: "searched ^[\($0) time](inflect: true)") }),
            (.edit, { AttributedString(localized: "edited ^[\($0) file](inflect: true)") }),
            (.command, { AttributedString(localized: "ran ^[\($0) command](inflect: true)") }),
            (.other, { AttributedString(localized: "used ^[\($0) tool](inflect: true)") }),
        ]
        let parts = clauses.compactMap { kind, clause in
            tally(kind) > 0 ? String(clause(tally(kind)).characters) : nil
        }
        let joined = ListFormatter.localizedString(byJoining: parts)
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}

/// One stretch of thinking: a reply may think, answer, then think again before going on.
struct ChatReasoning: Equatable, Hashable, Sendable {
    var text: String
    /// Characters of reply text that had arrived when this stretch began.
    let textOffset: Int
    /// Until the answer resumed, or the reply ended; nil while it is still thinking.
    var duration: TimeInterval?

    var displayText: String {
        guard let last = text.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(text[...last])
    }

    /// Codex opens each summary part with a bolded line, which names what it is thinking about.
    var heading: String? {
        text.split(whereSeparator: \.isNewline).reversed().lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 4 && $0.hasPrefix("**") && $0.hasSuffix("**") }
            .map { String($0.dropFirst(2).dropLast(2)) }
    }
}

enum ChatSegment: Equatable, Hashable {
    case text(String)
    case search(ChatSearch)
    case tools([ChatToolUse])
    case reasoning(ChatReasoning)
}
