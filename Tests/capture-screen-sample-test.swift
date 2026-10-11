import CoreGraphics
import Foundation

@main
struct CaptureScreenSampleTests {
    static func main() {
        let width = 2400, height = 1600
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = x % 2 == 0 ? 255 : 0
                bytes[offset + 1] = y < height / 2 ? 0 : 255
                bytes[offset + 2] = 0
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let bounds = CGRect(x: -100, y: 40, width: 1200, height: 800)
        let top = CaptureScreenSample.pixel(at: CGPoint(x: -100, y: 839.75), in: bounds, image: image)!
        precondition(top == CGPoint(x: 0, y: 0))
        precondition(CaptureScreenSample.hex(image: image, pixel: top) == "#FF0000")
        let adjacent = CaptureScreenSample.pixel(at: CGPoint(x: -99.25, y: 839.75), in: bounds, image: image)!
        precondition(adjacent == CGPoint(x: 1, y: 0))
        precondition(CaptureScreenSample.hex(image: image, pixel: adjacent) == "#000000")
        let bottom = CaptureScreenSample.pixel(at: CGPoint(x: 1099.75, y: 40), in: bounds, image: image)!
        precondition(bottom == CGPoint(x: 2399, y: 1599))
        precondition(CaptureScreenSample.hex(image: image, pixel: bottom) == "#00FF00")
        precondition(CaptureScreenSample.pixel(at: CGPoint(x: 1101, y: 40), in: bounds, image: image) == nil)
        precondition(CaptureScreenSample.pixel(at: CGPoint(x: CGFloat.nan, y: 40), in: bounds, image: image) == nil)
        precondition(CaptureScreenSample.pixel(at: .zero, in: .zero, image: image) == nil)
        print("Screen sampling: Retina pixels, adjacent one-pixel stripes, inverted Y and screen edges")
    }
}
