import SwiftUI

struct CaptureVideoStrip: View {
    let state: CaptureVideoState
    @Environment(\.metrics) private var metrics
    @State private var dragging = false

    var body: some View {
        VStack(spacing: metrics.spacing.xs) {
            GeometryReader { geometry in
                let width = geometry.size.width, height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(state.thumbnails.indices, id: \.self) { index in
                            Image(decorative: state.thumbnails[index], scale: 1)
                                .resizable().scaledToFill()
                                .frame(width: width / Double(state.thumbnails.count), height: height)
                                .clipped()
                        }
                    }.frame(width: width, height: height).background(Theme.Colors.controlSurface)
                    Canvas { context, size in
                        func x(_ time: Double) -> CGFloat { time / state.info.duration * size.width }
                        func fill(_ start: Double, _ end: Double, _ color: Color) {
                            context.fill(
                                Path(CGRect(x: x(start), y: 0, width: x(end - start), height: size.height)),
                                with: .color(color))
                        }
                        fill(0, state.edit.start, Theme.Colors.panelScrim)
                        fill(state.edit.end, state.info.duration, Theme.Colors.panelScrim)
                        for cut in state.edit.cuts { fill(cut.start, cut.end, .red.opacity(0.65)) }
                        for hold in state.edit.holds {
                            context.fill(
                                Path(
                                    CGRect(
                                        x: x(hold.position), y: 0,
                                        width: metrics.spacing.xxs, height: size.height)), with: .color(.cyan)
                            )
                        }
                        for effect in state.edit.effects {
                            let rect = CGRect(
                                x: x(effect.start), y: size.height - metrics.spacing.sm,
                                width: x(effect.end - effect.start), height: metrics.spacing.sm)
                            context.fill(Path(rect), with: .color(.accentColor.opacity(0.8)))
                        }
                        context.fill(
                            Path(
                                CGRect(
                                    x: x(state.playhead), y: 0, width: metrics.spacing.xxs,
                                    height: size.height)), with: .color(.white))
                    }.allowsHitTesting(false)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged {
                                state.seek(
                                    to: min(
                                        state.info.duration,
                                        max(0, $0.location.x / width * state.info.duration)))
                            }
                        )
                        .accessibilityLabel(String(localized: "Video Playhead"))
                        .accessibilityValue(
                            "\(state.playhead.formatted(.number.precision(.fractionLength(1)))) seconds"
                        )
                        .accessibilityAdjustableAction {
                            state.seek(to: state.playhead + ($0 == .increment ? 0.1 : -0.1))
                        }
                    handle(start: true, width: width, height: height)
                    handle(start: false, width: width, height: height)
                }.coordinateSpace(name: "videoTimeline").clipped()
            }.frame(height: metrics.scaled(Theme.Size.captureVideoTimeline))
            HStack {
                timeField(
                    String(localized: "Trim Start"),
                    value: Binding(
                        get: { state.edit.start },
                        set: { value in
                            state.change { $0.start = value }
                        }))
                Spacer()
                Text("\(state.playhead.formatted(.number.precision(.fractionLength(1)))) s").monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                timeField(
                    String(localized: "Trim End"),
                    value: Binding(
                        get: { state.edit.end },
                        set: { value in
                            state.change { $0.end = value }
                        }))
            }
        }.task { await state.loadThumbnails() }.task { await state.observePlayback() }
    }

    private func handle(start: Bool, width: CGFloat, height: CGFloat) -> some View {
        let value = start ? state.edit.start : state.edit.end
        return RoundedRectangle(cornerRadius: metrics.spacing.xxs, style: .continuous).fill(Color.accentColor)
            .frame(width: metrics.scaled(Theme.Size.captureHandle), height: height)
            .frame(width: metrics.scaled(Theme.Size.captureTool)).contentShape(Rectangle())
            .position(
                x: min(
                    width - metrics.spacing.xs, max(metrics.spacing.xs, value / state.info.duration * width)),
                y: height / 2
            )
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("videoTimeline"))
                    .onChanged { gesture in
                        if !dragging { state.beginEditing(); dragging = true }
                        let time = min(
                            state.info.duration, max(0, gesture.location.x / width * state.info.duration))
                        state.change {
                            if start {
                                $0.start = min(time, $0.end - min(0.1, state.info.duration))
                            } else {
                                $0.end = max(time, $0.start + min(0.1, state.info.duration))
                            }
                        }
                    }
                    .onEnded { _ in
                        state.endEditing(); dragging = false
                    }
            )
            .accessibilityLabel(
                start ? String(localized: "Trim Start Handle") : String(localized: "Trim End Handle")
            )
            .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(1)))) seconds")
            .accessibilityAdjustableAction { direction in
                let time = value + (direction == .increment ? 0.1 : -0.1)
                state.change {
                    if start {
                        $0.start = min(max(0, time), $0.end - 0.1)
                    } else {
                        $0.end = max(min(state.info.duration, time), $0.start + 0.1)
                    }
                }
            }
    }

    private func timeField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            Text(title)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .captureField(metrics).frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                .accessibilityLabel(title)
        }
    }
}
