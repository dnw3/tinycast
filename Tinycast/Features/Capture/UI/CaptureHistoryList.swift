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
            EmptyResults(text: "No captures yet")
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
                            HStack(spacing: metrics.spacing.md) {
                                Thumbnail(url: directory.appendingPathComponent("\(entry.id)/thumbnail.png"))
                                    .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                                VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                                    Text(entry.title).font(metrics.typography.rowTitle)
                                    Text(entry.subtitle)
                                        .font(metrics.typography.bar).foregroundStyle(
                                            Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .font(metrics.typography.bar).foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(metrics.spacing.md)
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
