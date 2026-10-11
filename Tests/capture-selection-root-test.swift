import AppKit

@main
struct CaptureSelectionRootTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for scale in [CGFloat(1), 2] {
            let width = Int(48 * scale), height = Int(32 * scale)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let source = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            for x in 0..<width {
                source.setFillColor(CGColor(gray: x.isMultiple(of: 2) ? 0 : 1, alpha: 1))
                source.fill(CGRect(x: x, y: 0, width: 1, height: height))
            }
            let image = source.makeImage()!
            let overlay = NSView()
            let root = CaptureSelectionRootView(frame: CGRect(x: 0, y: 0, width: 48, height: 32),
                selection: overlay, image: image, scale: scale)
            let window = NSWindow(contentRect: root.frame, styleMask: [], backing: .buffered, defer: false)
            window.contentView = root
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            let rendered = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            rendered.scaleBy(x: scale, y: scale)
            root.layer!.render(in: rendered)
            let bytes = rendered.data!.assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = (height / 2 * width + x) * 4
                precondition(bytes[offset] == (x.isMultiple(of: 2) ? 0 : 255), "Frozen pixels must stay aligned")
                precondition(bytes[offset + 3] == 255, "Desktop background must be fully opaque")
            }
            overlay.needsDisplay = true
            overlay.displayIfNeeded()
            precondition(root.layer!.sublayers!.first!.animationKeys() == nil)
            window.contentView = nil
        }
        print("Frozen desktop layer: native pixel alignment, opacity and no implicit animation at 1x/2x passed")
    }
}
