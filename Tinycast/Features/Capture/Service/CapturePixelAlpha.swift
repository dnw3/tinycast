import Accelerate
import Foundation

enum CapturePixelAlpha {
    nonisolated static func unpremultiply(_ pixels: UnsafeMutableRawBufferPointer) throws {
        guard !pixels.isEmpty, pixels.count.isMultiple(of: 4) else { throw CaptureRasterError.invalidRow }
        var source = vImage_Buffer(
            data: pixels.baseAddress, height: 1, width: vImagePixelCount(pixels.count / 4), rowBytes: pixels.count)
        var destination = source
        guard vImageUnpremultiplyData_RGBA8888(&source, &destination, vImage_Flags(kvImageDoNotTile)) == kvImageNoError
        else { throw CaptureRasterError.invalidRow }
    }
}
