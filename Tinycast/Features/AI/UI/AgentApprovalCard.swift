import SwiftUI

/// The one loud thing in an agent's turn: what it wants to do, risen from the composer's top edge.
struct AgentApprovalCard: View {
    let request: AgentApprovalRequest
    let workspace: AgentWorkspace
    let agent: String
    let position: (index: Int, count: Int)
    let onAnswer: (AgentApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                ApprovalSymbol(name: request.symbol, tone: request.deletes ? .danger : .neutral)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(request.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(verbatim: "\(agent) · \(request.place(in: workspace))")
                        .font(.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: Theme.Spacing.md)
                if position.count > 1 {
                    Text(verbatim: "\(position.index + 1) / \(position.count)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            ApprovalDetail(request: request, workspace: workspace)
            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(Theme.Spacing.lg)
        .background {
            Color.clear.glassEffect(
                .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Waiting for your approval: \(request.title)"))
    }

    /// A delete takes a click: no key allows it, and no grant covers the next one.
    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(String(localized: "Don't Allow")) { onAnswer(.deny) }
                .buttonStyle(.modalAction(.cancel, fillsWidth: false))
                .tooltip(keyCaps: ["⎋"])
            Spacer(minLength: Theme.Spacing.md)
            if AgentGrants.admits(request, in: workspace) {
                Button(String(localized: "Allow This Chat")) { onAnswer(.allowForChat) }
                    .buttonStyle(.modalAction(.standard, fillsWidth: false))
                    .tooltip(keyCaps: ["⌥↵"])
            }
            Button(request.allowTitle) { onAnswer(.allow) }
                .buttonStyle(.modalAction(request.deletes ? .destructive : .primary, fillsWidth: false))
                .tooltip(keyCaps: request.deletes ? [] : ["↵"])
        }
    }
}

/// The dialog's glyph tile at the composer's scale; the tone tints the glyph, never the buttons.
private struct ApprovalSymbol: View {
    let name: String
    let tone: DialogTone

    var body: some View {
        Image(systemName: name)
            .font(Theme.Typography.composerSymbol)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tone == .neutral ? Theme.Colors.textSecondary : tone.tint)
            .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                    .fill(tone.tileFill))
            .accessibilityHidden(true)
    }
}

/// The command, diff or path itself: the card's point is that it is read before it is answered.
private struct ApprovalDetail: View {
    let request: AgentApprovalRequest
    let workspace: AgentWorkspace

    var body: some View {
        switch request.action {
        case .command(let line), .inspection(let line, _):
            ApprovalCode { Text(line) }
        case .fileChanges(let changes):
            ApprovalCode {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                        ApprovalFileChange(change: change, workspace: workspace, titled: changes.count > 1)
                    }
                }
            }
        case .read(let path):
            ApprovalCode { Text(path) }
        case .tool(_, let summary):
            if !summary.isEmpty { ApprovalCode { Text(summary) } }
        }
    }
}

private struct ApprovalFileChange: View {
    let change: AgentApprovalRequest.FileChange
    let workspace: AgentWorkspace
    let titled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if titled || change.diff.isEmpty {
                Text(verbatim: heading)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if !change.diff.isEmpty {
                Text(ChatDiffText.attributed(change.diff))
            }
        }
    }

    private var heading: String {
        let path = AgentApprovalRequest.display(change.path, in: workspace)
        switch change.kind {
        case .add: return String(localized: "New file · \(path)")
        case .delete: return String(localized: "Delete · \(path)")
        case .update: return path
        case .move(let destination):
            return "\(path) → \(AgentApprovalRequest.display(destination, in: workspace))"
        }
    }

}

/// Shown whole when it fits, scrolled inside a capped box when it does not.
private struct ApprovalCode<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        // Sized by its content, not the room offered, which measured the stack too tall.
        ScrollView { padded }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Theme.Size.chatApprovalDetail)
            .fixedSize(horizontal: false, vertical: true)
            .background(shape.fill(Theme.Colors.cardFill))
        .overlay(shape.stroke(Theme.Colors.cardStroke))
        .clipShape(shape)
    }

    private var padded: some View {
        content
            .font(Theme.Typography.code)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
    }
}

extension AgentApprovalRequest {
    fileprivate var symbol: String {
        switch action {
        case .command: return "terminal"
        case .fileChanges(let changes):
            if deletes { return "trash" }
            guard changes.count == 1, let change = changes.first else { return "pencil" }
            switch change.kind {
            case .add: return "doc.badge.plus"
            case .move: return "folder"
            case .update, .delete: return "pencil"
            }
        case .read, .inspection: return "doc.text"
        case .tool: return "wrench.and.screwdriver"
        }
    }

    /// A verb and its object, as the agent would say it: "Edit AGENTS.md", "Delete 3 files".
    var title: String {
        switch action {
        case .command:
            return String(localized: "Run a command")
        case .fileChanges(let changes):
            guard changes.count == 1, let change = changes.first else {
                let count = changes.count
                return changes.allSatisfy({ $0.kind == .delete })
                    ? String(AttributedString(localized: "Delete ^[\(count) file](inflect: true)").characters)
                    : String(AttributedString(localized: "Change ^[\(count) file](inflect: true)").characters)
            }
            let name = (change.path as NSString).lastPathComponent
            switch change.kind {
            case .add: return String(localized: "Create \(name)")
            case .delete: return String(localized: "Delete \(name)")
            case .update: return String(localized: "Edit \(name)")
            case .move(let destination):
                let renames = (destination as NSString).deletingLastPathComponent
                    == (change.path as NSString).deletingLastPathComponent
                return renames ? String(localized: "Rename \(name)") : String(localized: "Move \(name)")
            }
        case .read, .inspection:
            return String(localized: "Read outside the folder")
        case .tool(let name, _):
            return String(localized: "Use \(name)")
        }
    }

    fileprivate var allowTitle: String {
        guard case .fileChanges(let changes) = action else { return String(localized: "Allow") }
        if changes.allSatisfy({ $0.kind == .delete }) { return String(localized: "Delete") }
        if changes.allSatisfy({ $0.kind == .add }) { return String(localized: "Create") }
        return String(localized: "Allow")
    }

    /// Where it happens: a place inside the folder by the folder's name, anywhere else by its path.
    fileprivate func place(in workspace: AgentWorkspace) -> String {
        switch action {
        case .command, .tool:
            return workspace.folder.lastPathComponent
        case .fileChanges(let changes):
            let directories = Set(changes.map { ($0.target as NSString).deletingLastPathComponent })
            guard directories.count == 1, let directory = directories.first else {
                return workspace.folder.lastPathComponent
            }
            return Self.display(directory, in: workspace)
        case .read(let path):
            return Self.display((path as NSString).deletingLastPathComponent, in: workspace)
        case .inspection(_, let paths):
            let outside = paths.first { !workspace.contains($0) } ?? workspace.folder.path
            return Self.display(outside, in: workspace)
        }
    }

    static func display(_ path: String, in workspace: AgentWorkspace) -> String {
        let name = workspace.folder.lastPathComponent
        guard workspace.contains(path) else {
            return (resolved(path, in: workspace) as NSString).abbreviatingWithTildeInPath
        }
        let relative = String(resolved(path, in: workspace).dropFirst(workspace.root.count))
        return relative.isEmpty ? name : "\(name)/\(relative)"
    }

    private static func resolved(_ path: String, in workspace: AgentWorkspace) -> String {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path) : workspace.folder.appendingPathComponent(path)
        return url.standardizedFileURL.path
    }
}
