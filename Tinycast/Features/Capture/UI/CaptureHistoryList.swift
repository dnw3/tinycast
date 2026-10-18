import SwiftUI

struct CaptureHistoryList: View {
    let rows: [CaptureHistoryEntry]
    let directory: URL
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    let onDrag: (CaptureHistoryEntry) -> NSItemProvider
    @Environment(\.metrics) private var metrics

    var body: some View {
        if rows.isEmpty {
            EmptyResults(text: String(localized: "No captures yet"))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            if index == 0
                                || !Calendar.current.isDate(rows[index - 1].date, inSameDayAs: entry.date)
                            {
                                SectionHeader(
                                    title: entry.date.formatted(date: .abbreviated, time: .omitted),
                                    isFirst: index == 0)
                            }
                            Row(entry: entry, directory: directory, selected: selection == index)
                            .selectionFrame(selection == index)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onActivate(index) }
                            .onTapGesture { onSelect(index) }
                            .onRightClick { onActions(index) }
                            .onDrag { onDrag(entry) }
                            .id(entry.id.uuidString)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(selection == index ? .isSelected : [])
                            .accessibilityAction { onActivate(index) }
                        }
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.top, metrics.spacing.xs)
                    .padding(.bottom, metrics.spacing.md)
                    .hideNativeScrollers()
                    .scrollOriginAnchor()
                }
                .edgeDissolve()
                .thinScrollbar()
                .scrollFollowsSelection(
                    scroll, row: rows.indices.contains(selection) ? rows[selection].id.uuidString : nil,
                    atOrigin: selection == 0, proxy: proxy)
            }
        }
    }

    private struct Row: View {
        let entry: CaptureHistoryEntry
        let directory: URL
        let selected: Bool
        @State private var hovered = false
        @Environment(\.metrics) private var metrics

        private var fill: Color {
            if selected { return Theme.Colors.selection }
            return hovered ? Theme.Colors.rowHover : .clear
        }

        var body: some View {
            HStack(spacing: metrics.spacing.md) {
                Thumbnail(url: directory.appendingPathComponent("\(entry.id)/thumbnail.png"))
                    .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
                VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                    Text(entry.title).font(metrics.typography.rowTitle)
                    Text(entry.displaySubtitle)
                        .font(metrics.typography.bar).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(metrics.typography.bar).foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.sm)
            .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
            .armedHover($hovered)
        }
    }

    private struct Thumbnail: View {
        let url: URL
        @State private var image: NSImage?
        @Environment(\.metrics) private var metrics
        var body: some View {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    SymbolImage(name: "photo", size: metrics.size.rowIcon)
                }
            }
            .task(id: url) { image = await ImageThumbnail.loadAsync(url, maxPixel: 96) }
        }
    }
}

extension CaptureHistoryEntry {
    /// `subtitle` stays the model's English fact; this is the same line in the reader's language.
    var displaySubtitle: String {
        if let animationDuration {
            return "GIF · \(Duration.seconds(animationDuration).formatted(.time(pattern: .minuteSecond)))"
        }
        if let videoDuration {
            let time = Duration.seconds(videoDuration).formatted(.time(pattern: .minuteSecond))
            return draft ? String(localized: "Video draft · \(time)") : String(localized: "Video · \(time)")
        }
        if draft { return String(localized: "Editable draft") }
        return editable ? String(localized: "Editable original") : String(localized: "Flattened image")
    }
}
