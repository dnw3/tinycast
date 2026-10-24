import AppKit
import SwiftUI

/// A flag beside text: the emoji font's own, or Taiwan's drawn, which China-region Macs blank.
struct ProxyFlag: View {
    let emoji: String
    /// The surrounding text's point size, which a drawn flag cannot take from the font.
    var size = NSFont.systemFontSize

    var body: some View {
        if emoji == ProxyRegion.taiwan.flagEmoji {
            Text(Image(nsImage: ProxyFlagArtwork.taiwan(size: size)))
                .accessibilityLabel(Text(ProxyRegion.taiwan.title))
        } else {
            Text(emoji)
        }
    }
}

/// Flags drawn in the emoji font's manner: waved once, lit on the rise, on the font's own metrics.
@MainActor
enum ProxyFlagArtwork {
    private static var inline: [CGFloat: NSImage] = [:]
    private static var menu: [String: NSImage] = [:]

    /// Laid out as the glyph is: a 1.08 em advance standing on the baseline.
    static func taiwan(size: CGFloat) -> NSImage {
        if let image = inline[size] { return image }
        let image = NSImage(size: NSSize(width: size * 1.08, height: size * 0.72), flipped: false) { _ in
            drawTaiwan(in: NSRect(x: size * 0.09, y: size * 0.105, width: size * 0.87, height: size * 0.56))
            return true
        }
        image.accessibilityDescription = ProxyRegion.taiwan.title
        inline[size] = image
        return image
    }

    /// The flag alone, trimmed to its edges and as wide as a menu's image column.
    static func menuImage(emoji: String) -> NSImage {
        if let image = menu[emoji] { return image }
        let flag = NSRect(x: 0, y: 0, width: 16, height: 11.6)
        let image = NSImage(size: NSSize(width: 16, height: 12), flipped: false) { _ in
            if emoji == ProxyRegion.taiwan.flagEmoji {
                drawTaiwan(in: flag.insetBy(dx: 0, dy: 16 * 0.035))
            } else {
                // The glyph's flag spans 0.09–0.96 em across and 0.07–0.70 em above the baseline.
                let em = flag.width / 0.87
                let font = NSFont.systemFont(ofSize: em)
                (emoji as NSString).draw(
                    at: NSPoint(x: -0.09 * em, y: -0.07 * em + font.descender),
                    withAttributes: [.font: font])
            }
            return true
        }
        menu[emoji] = image
        return image
    }

    private static let red = CGColor(srgbRed: 0.93, green: 0.11, blue: 0.14, alpha: 1)
    private static let blue = CGColor(srgbRed: 0.05, green: 0.12, blue: 0.55, alpha: 1)

    /// Strips of the flat flag, each lifted and lit by where it sits on the wave.
    private static func drawTaiwan(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let strips = 40
        let amplitude = rect.height * 0.065
        let shape = CGPath(
            roundedRect: rect, cornerWidth: rect.height * 0.09, cornerHeight: rect.height * 0.09, transform: nil)
        for index in 0..<strips {
            let start = Double(index) / Double(strips)
            let end = Double(index + 1) / Double(strips)
            let phase = 2 * Double.pi * ((start + end) / 2 - 0.21) / 1.26
            context.saveGState()
            // Twice as wide as its step, so the next strip covers this one's soft edge, not a gap.
            context.clip(
                to: CGRect(
                    x: rect.minX + rect.width * start, y: rect.minY - amplitude * 2,
                    width: rect.width * (end - start) * 2, height: rect.height + amplitude * 4))
            context.translateBy(x: 0, y: -amplitude * cos(phase))
            context.addPath(shape)
            context.clip()
            drawFlat(in: rect, context: context)
            let light = sin(phase)
            context.setFillColor(
                light > 0 ? CGColor(gray: 1, alpha: 0.22 * light) : CGColor(gray: 0, alpha: -0.2 * light))
            context.fill(rect)
            context.addPath(shape)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            context.setLineWidth(rect.height * 0.06)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Red, with a blue canton holding a white sun of twelve rays.
    private static func drawFlat(in rect: NSRect, context: CGContext) {
        context.setFillColor(red)
        context.fill(rect)
        let canton = CGRect(x: rect.minX, y: rect.midY, width: rect.width / 2, height: rect.height / 2)
        context.setFillColor(blue)
        context.fill(canton)
        let center = CGPoint(x: canton.midX, y: canton.midY)
        let unit = canton.height
        let rays = CGMutablePath()
        for index in 0..<24 {
            let angle = Double(index) * .pi / 12 + .pi / 2
            let radius = index.isMultiple(of: 2) ? unit * 0.375 : unit * 0.2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { rays.move(to: point) } else { rays.addLine(to: point) }
        }
        rays.closeSubpath()
        context.setFillColor(.white)
        context.addPath(rays)
        context.fillPath()
        context.setFillColor(blue)
        context.fillEllipse(in: CGRect(x: center.x - unit * 0.2125, y: center.y - unit * 0.2125,
                                       width: unit * 0.425, height: unit * 0.425))
        context.setFillColor(.white)
        context.fillEllipse(in: CGRect(x: center.x - unit * 0.1875, y: center.y - unit * 0.1875,
                                       width: unit * 0.375, height: unit * 0.375))
    }
}
