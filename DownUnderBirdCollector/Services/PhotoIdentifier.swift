import UIKit

/// Suggests the species in a photo with the bundled iNaturalist bird
/// classifier (MobileNet V2, Google, Apache-2.0) on TensorFlow Lite. Only
/// field-guide species are suggested; the user always confirms.
/// Mirrors `web/src/js/photoid.js`.
actor PhotoIdentifier {
    static let modelName = "BirdPhotoClassifier"

    static var isAvailable: Bool {
        Bundle.main.url(forResource: modelName, withExtension: "tflite") != nil
            && Bundle.main.url(forResource: "\(modelName)_labels", withExtension: "txt") != nil
    }

    private let interpreter: TFLiteInterpreter
    nonisolated let codes: [String?]

    /// Loads the model (fast: 3.5 MB); call off the main thread.
    init(species: [Species], bundle: Bundle = .main) throws {
        guard let modelURL = bundle.url(forResource: Self.modelName, withExtension: "tflite"),
              let labelsURL = bundle.url(forResource: "\(Self.modelName)_labels", withExtension: "txt") else {
            throw SoundIdentifier.SoundIDError.notBundled
        }
        let labels = PhotoIDCore.parseLabels(try String(contentsOf: labelsURL, encoding: .utf8))
        codes = PhotoIDCore.mapLabels(labels, to: species)
        interpreter = try TFLiteInterpreter(modelPath: modelURL.path)
    }

    func identify(_ image: UIImage) throws -> PhotoIDCore.Result {
        guard let pixels = Self.pixels(of: image) else { throw MLClassifier.ClassifierError.imageConversionFailed }
        let output = try interpreter.run(bytes: pixels)
        return PhotoIDCore.suggestions(PhotoIDCore.dequantize(output), codes: codes)
    }

    /// The photo's centre square at 224 × 224 (upright), as RGB bytes.
    static func pixels(of image: UIImage) -> [UInt8]? {
        let side = PhotoIDCore.inputSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            // Aspect-fill: scale the shorter side to 224 and centre (draw handles orientation).
            let scale = CGFloat(side) / min(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        guard let cgImage = upright.cgImage else { return nil }

        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var rgb = [UInt8]()
        rgb.reserveCapacity(side * side * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgb.append(rgba[i])
            rgb.append(rgba[i + 1])
            rgb.append(rgba[i + 2])
        }
        return rgb
    }
}
