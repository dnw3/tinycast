import Accelerate
import Foundation

enum CaptureImageProcessing {
    nonisolated static func blurred(
        reader: CaptureCompositeReader, rect: CGRect, bounds: CGRect, adjustments: CaptureImageAdjustments?, radius: Int
    ) throws -> Data {
        guard (1...24).contains(radius) else { throw CaptureRasterError.invalidSize }
        let expanded = rect.insetBy(dx: -CGFloat(radius), dy: -CGFloat(radius)).intersection(bounds)
        var input = try pixels(reader: reader, rect: expanded, bounds: bounds, adjustments: adjustments)
        var output = Data(count: Int(rect.width * rect.height) * 4)
        try input.withUnsafeMutableBytes { sourceBytes in
            try output.withUnsafeMutableBytes { destinationBytes in
                var source = vImage_Buffer(data: sourceBytes.baseAddress, height: vImagePixelCount(expanded.height),
                    width: vImagePixelCount(expanded.width), rowBytes: Int(expanded.width) * 4)
                var premultiplied = source
                guard vImagePremultiplyData_RGBA8888(&source, &premultiplied, vImage_Flags(kvImageDoNotTile)) == kvImageNoError
                else { throw CaptureRasterError.invalidTile }
                var destination = vImage_Buffer(data: destinationBytes.baseAddress, height: vImagePixelCount(rect.height),
                    width: vImagePixelCount(rect.width), rowBytes: Int(rect.width) * 4)
                guard vImageTentConvolve_ARGB8888(&premultiplied, &destination, nil,
                    vImagePixelCount(rect.minX - expanded.minX), vImagePixelCount(rect.minY - expanded.minY),
                    UInt32(radius * 2 + 1), UInt32(radius * 2 + 1), nil,
                    vImage_Flags(kvImageEdgeExtend | kvImageDoNotTile)) == kvImageNoError
                else { throw CaptureRasterError.invalidTile }
            }
        }
        return output
    }

    nonisolated static func pixels(
        reader: CaptureCompositeReader, rect: CGRect, bounds: CGRect, adjustments: CaptureImageAdjustments?
    ) throws -> Data {
        guard let adjustments, !adjustments.isIdentity else { return try reader.read(rect: rect) }
        guard adjustments.isValid else { throw CaptureRasterError.invalidTile }
        var pixels: Data
        if adjustments.sharpness > 0 {
            pixels = try sharpen(reader: reader, rect: rect, bounds: bounds, amount: adjustments.sharpness)
        } else { pixels = try reader.read(rect: rect) }
        let divisor: Int32 = 1024
        let direction = adjustments.inverted ? -1.0 : 1.0
        let luma = [0.2126, 0.7152, 0.0722]
        var matrix = [Int16](repeating: 0, count: 16)
        for source in 0..<3 {
            for destination in 0..<3 {
                let value = (1 - adjustments.saturation) * luma[source]
                    + (source == destination ? adjustments.saturation : 0)
                matrix[source * 4 + destination] = Int16(
                    (value * adjustments.contrast * direction * Double(divisor)).rounded())
            }
        }
        matrix[15] = Int16(divisor)
        let offset = ((1 - adjustments.contrast) * 0.5 + adjustments.brightness) * 255 * direction
            + (adjustments.inverted ? 255 : 0)
        let bias = Int32((offset * Double(divisor)).rounded()) + divisor / 2
        let biases = [bias, bias, bias, divisor / 2]
        try pixels.withUnsafeMutableBytes { bytes in
            var source = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(rect.height),
                width: vImagePixelCount(rect.width), rowBytes: Int(rect.width) * 4)
            var destination = source
            guard vImageMatrixMultiply_ARGB8888(&source, &destination, matrix, divisor, nil, biases,
                vImage_Flags(kvImageDoNotTile)) == kvImageNoError
            else { throw CaptureRasterError.invalidTile }
        }
        return pixels
    }

    nonisolated private static func sharpen(
        reader: CaptureCompositeReader, rect: CGRect, bounds: CGRect, amount: Double
    ) throws -> Data {
        let expanded = rect.insetBy(dx: -1, dy: -1).intersection(bounds)
        var input = try reader.read(rect: expanded)
        var output = Data(count: Int(rect.width * rect.height) * 4)
        let strength = Int16((amount * 256).rounded())
        let kernel: [Int16] = [0, -strength, 0, -strength, 256 + 4 * strength, -strength, 0, -strength, 0]
        let identity: [Int16] = [0, 0, 0, 0, 256, 0, 0, 0, 0]
        try input.withUnsafeMutableBytes { sourceBytes in
            try output.withUnsafeMutableBytes { destinationBytes in
                var source = vImage_Buffer(data: sourceBytes.baseAddress, height: vImagePixelCount(expanded.height),
                    width: vImagePixelCount(expanded.width), rowBytes: Int(expanded.width) * 4)
                var destination = vImage_Buffer(data: destinationBytes.baseAddress, height: vImagePixelCount(rect.height),
                    width: vImagePixelCount(rect.width), rowBytes: Int(rect.width) * 4)
                try kernel.withUnsafeBufferPointer { color in
                    try identity.withUnsafeBufferPointer { alpha in
                        var kernels = [color.baseAddress, color.baseAddress, color.baseAddress, alpha.baseAddress]
                        let divisors: [Int32] = [256, 256, 256, 256]
                        guard vImageConvolveMultiKernel_ARGB8888(&source, &destination, nil,
                            vImagePixelCount(rect.minX - expanded.minX), vImagePixelCount(rect.minY - expanded.minY),
                            &kernels, 3, 3, divisors, nil, nil,
                            vImage_Flags(kvImageEdgeExtend | kvImageDoNotTile)) == kvImageNoError
                        else { throw CaptureRasterError.invalidTile }
                    }
                }
            }
        }
        return output
    }
}
