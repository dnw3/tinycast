import Foundation

extension ChatToolUse {
    var label: String {
        if let kind { return Self.label(kind, title: title, state: state, exitCode: detail?.exitCode) }
        if state == .running {
            return origin.isEmpty ? String(localized: "Calling \(title)")
                : String(localized: "Calling \(origin) · \(title)")
        }
        return origin.isEmpty ? String(localized: "Called \(title)")
            : String(localized: "Called \(origin) · \(title)")
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
    /// What ran, by kind, then what failed and what the reader refused, which never ran at all.
    var completedLabel: String {
        let ran = filter { $0.state != .declined }
        var label = allSatisfy({ $0.kind != nil }) ? ran.agentSummary : String(localized: "Called \(count) tools")
        if failedCount > 0 { label = String(localized: "\(label) · \(failedCount) failed") }
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
