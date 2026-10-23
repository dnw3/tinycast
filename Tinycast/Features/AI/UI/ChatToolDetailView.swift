import SwiftUI

/// A step opened up: what it was given above the rule, what it gave back below, on a code card.
struct ChatToolDetailView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.chatAgentWorkspace) private var workspace
    let use: ChatToolUse
    let detail: ChatToolDetail

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            if let explanation = detail.explanation {
                Text(explanation)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            HStack(alignment: .top, spacing: metrics.spacing.md) {
                ChatToolExcerpt(text: detail.input, fromEnd: false, naming: naming)
                    .foregroundStyle(Theme.Colors.textPrimary)
                ChatCopyButton(
                    text: detail.input,
                    label: use.kind == .command
                        ? String(localized: "Copy Command") : String(localized: "Copy Input"))
            }
            if let output {
                Rectangle()
                    .fill(Theme.Colors.cardStroke)
                    .frame(height: Theme.Size.hairline)
                ChatToolExcerpt(
                    text: output, fromEnd: use.kind == .command, droppedEarlier: detail.isOutputTrimmed)
                .foregroundStyle(Theme.Colors.textSecondary)
            } else if use.kind == .command, use.state == .completed {
                Text("No output")
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(shape.stroke(Theme.Colors.cardStroke))
    }

    private var naming: ((_ before: String, _ after: String) -> String)? {
        guard use.kind == .edit else { return nil }
        return fileHeading
    }

    /// One line per file, its path as the approval card wrote it: inside the folder by the folder.
    private func fileHeading(before: String, after: String) -> String {
        let display = { (path: String) in
            workspace.map { AgentApprovalRequest.display(path, in: $0) }
                ?? (path as NSString).abbreviatingWithTildeInPath
        }
        switch (before, after) {
        case ("/dev/null", let path): return String(localized: "New file · \(display(path))")
        case (let path, "/dev/null"): return String(localized: "Delete · \(display(path))")
        case (let source, let destination) where source != destination:
            return "\(display(source)) → \(display(destination))"
        default: return display(after)
        }
    }

    /// An edit's diff is the point; what the CLI printed after one only matters when it failed.
    private var output: String? {
        guard use.kind != .edit || use.state == .failed,
            let output = detail.output?.trimmingCharacters(in: .newlines), !output.isEmpty
        else { return nil }
        return output
    }
}

/// Whole when short; else its first or last lines, and a way to the rest without a second scroll.
private struct ChatToolExcerpt: View {
    @Environment(\.metrics) private var metrics
    let text: String
    let fromEnd: Bool
    /// A diff's file-naming pairs as one line each; set, the block is coloured as a diff.
    var naming: ((_ before: String, _ after: String) -> String)?
    var droppedEarlier = false
    @State private var showsAll = false

    var body: some View {
        let whole = text.trimmingCharacters(in: .newlines)
        let limit = Theme.Size.chatToolPreviewLines
        let excerpt = ChatToolDetail.excerpt(of: whole, lines: limit, fromEnd: fromEnd)
        let shown = showsAll ? whole : excerpt.text
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            if droppedEarlier, showsAll || excerpt.hidden == 0 {
                Text("Earlier output wasn't kept")
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Group {
                if let naming {
                    Text(ChatDiffText.attributed(shown, naming: naming))
                } else {
                    Text(verbatim: shown)
                }
            }
            .font(metrics.typography.code)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if excerpt.hidden > 0 {
                Button {
                    showsAll.toggle()
                } label: {
                    Text(
                        showsAll
                            ? String(localized: "Show Less")
                            : String(localized: "Show All \(excerpt.hidden + limit) Lines"))
                }
                .buttonStyle(.plain)
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
