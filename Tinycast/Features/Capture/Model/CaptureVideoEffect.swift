import Foundation

struct CaptureVideoEffect: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case zoom, cover, text }

    var id = UUID()
    var kind: Kind
    var start: Double
    var end: Double
    var rect: CGRect
    var text = "Text"
    var color = CaptureColor(red: 0, green: 0, blue: 0)

    func isValid(duration: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end <= duration && end - start >= 0.01
            && CaptureGeometry.valid(rect) && rect.minX >= 0 && rect.minY >= 0
            && rect.maxX <= 1 && rect.maxY <= 1 && rect.width >= 0.025 && rect.height >= 0.025
            && text.utf8.count <= 2_048 && (kind != .text || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func contains(_ time: Double) -> Bool { time >= start && time < end }

    static func viewport(_ effects: [Self], at time: Double) -> CGRect {
        guard let effect = effects.last(where: { $0.kind == .zoom && $0.contains(time) }) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let side = max(effect.rect.width, effect.rect.height)
        return CGRect(x: min(1 - side, max(0, effect.rect.midX - side / 2)),
            y: min(1 - side, max(0, effect.rect.midY - side / 2)), width: side, height: side)
    }
}
