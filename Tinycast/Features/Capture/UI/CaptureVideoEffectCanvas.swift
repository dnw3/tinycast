import SwiftUI

struct CaptureVideoEffectCanvas: View {
    let state: CaptureVideoState
    @Environment(\.metrics) private var metrics
    @State private var original: CGRect?

    var body: some View {
        GeometryReader { geometry in
            if let effect = state.selectedEffect {
                let scale = min(
                    geometry.size.width / Double(state.info.size.width),
                    geometry.size.height / Double(state.info.size.height))
                let size = CGSize(
                    width: Double(state.info.size.width) * scale,
                    height: Double(state.info.size.height) * scale)
                let origin = CGPoint(
                    x: (geometry.size.width - size.width) / 2, y: (geometry.size.height - size.height) / 2)
                let rect = CGRect(
                    x: origin.x + effect.rect.minX * size.width, y: origin.y + effect.rect.minY * size.height,
                    width: effect.rect.width * size.width, height: effect.rect.height * size.height)
                ZStack(alignment: .topLeading) {
                    Rectangle().stroke(Color.accentColor, lineWidth: metrics.spacing.xxs)
                        .background(Color.accentColor.opacity(0.12)).contentShape(Rectangle())
                        .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                        .gesture(move(effect: effect, size: size))
                        .accessibilityLabel(String(localized: "Video Effect Position"))
                        .accessibilityHint(
                            String(
                                localized: "Drag to move. Use the percentage fields for precise placement."))
                    ForEach(0..<4, id: \.self) { corner in
                        Circle().fill(Color.accentColor)
                            .frame(
                                width: metrics.scaled(Theme.Size.captureHandle),
                                height: metrics.scaled(Theme.Size.captureHandle)
                            )
                            .frame(
                                width: metrics.scaled(Theme.Size.captureTool),
                                height: metrics.scaled(Theme.Size.captureTool)
                            )
                            .contentShape(Rectangle())
                            .position(
                                x: corner.isMultiple(of: 2) ? rect.minX : rect.maxX,
                                y: corner < 2 ? rect.minY : rect.maxY
                            )
                            .gesture(resize(effect: effect, corner: corner, size: size))
                            .accessibilityLabel(String(localized: "Resize Video Effect Corner \(corner + 1)"))
                    }
                    Text("Position on original frame").font(metrics.typography.bar)
                        .padding(metrics.spacing.sm).background(Theme.Colors.panelScrim)
                        .padding(metrics.spacing.sm).allowsHitTesting(false)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func move(effect: CaptureVideoEffect, size: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            let rect = begin(effect)
            state.changeEffect {
                $0.rect.origin = CGPoint(
                    x: min(1 - rect.width, max(0, rect.minX + value.translation.width / size.width)),
                    y: min(1 - rect.height, max(0, rect.minY + value.translation.height / size.height)))
            }
        }.onEnded { _ in end() }
    }

    private func resize(effect: CaptureVideoEffect, corner: Int, size: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            let rect = begin(effect), left = corner.isMultiple(of: 2), top = corner < 2
            let x = min(1, max(0, (left ? rect.minX : rect.maxX) + value.translation.width / size.width))
            let y = min(1, max(0, (top ? rect.minY : rect.maxY) + value.translation.height / size.height))
            let minX = left ? min(x, rect.maxX - 0.025) : rect.minX
            let minY = top ? min(y, rect.maxY - 0.025) : rect.minY
            let maxX = left ? rect.maxX : max(x, rect.minX + 0.025)
            let maxY = top ? rect.maxY : max(y, rect.minY + 0.025)
            state.changeEffect { $0.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) }
        }.onEnded { _ in end() }
    }

    private func begin(_ effect: CaptureVideoEffect) -> CGRect {
        if original == nil { original = effect.rect; state.beginEditing() }
        return original ?? effect.rect
    }

    private func end() { state.endEditing(); original = nil }
}
