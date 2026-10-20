import Foundation
import UIKit
import Vision
import CoreML

/// Wraps the bundled region-specific Core ML image classifier(s).
///
/// Models are named `BirdClassifier_<REGION>.mlmodel` and live in
/// `Resources/ML/` (see `scripts/train-model/README.md`). When a region has
/// no model the capture flow skips straight to choosing the species by hand.
///
/// The model emits `VNClassificationObservation` results where `identifier`
/// is the species' eBird code.
@MainActor
final class MLClassifier {
    enum ClassifierError: LocalizedError {
        case modelUnavailable(region: Region)
        case imageConversionFailed

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let region): return "No identification model for \(region.displayName) yet."
            case .imageConversionFailed: return "That photo couldn't be read."
            }
        }
    }

    private var cachedModels: [Region: VNCoreMLModel] = [:]
    private let topN = 5

    static func modelURL(for region: Region) -> URL? {
        let name = "BirdClassifier_\(region.rawValue)"
        return Bundle.main.url(forResource: name, withExtension: "mlmodelc")
    }

    static func isModelAvailable(for region: Region) -> Bool {
        modelURL(for: region) != nil
    }

    func classify(image: UIImage, region: Region) async throws -> [Prediction] {
        let model = try loadModel(region: region)
        guard let cgImage = image.cgImage else {
            throw ClassifierError.imageConversionFailed
        }
        let orientation = image.cgImageOrientation
        let topN = self.topN

        // `perform` is synchronous and fills `results`; run it off the main actor.
        return try await Task.detached(priority: .userInitiated) {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            let results = (request.results as? [VNClassificationObservation]) ?? []
            return results.prefix(topN).map {
                Prediction(speciesCode: $0.identifier, commonName: "", confidence: Double($0.confidence))
            }
        }.value
    }

    private func loadModel(region: Region) throws -> VNCoreMLModel {
        if let cached = cachedModels[region] { return cached }
        guard let url = Self.modelURL(for: region) else {
            throw ClassifierError.modelUnavailable(region: region)
        }
        let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: url))
        cachedModels[region] = visionModel
        return visionModel
    }
}

private extension UIImage {
    /// Maps UIImage's orientation into Vision's coordinate space.
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
