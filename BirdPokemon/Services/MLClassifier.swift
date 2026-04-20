import Foundation
import UIKit
import Vision
import CoreML

/// Wraps the bundled region-specific Core ML image classifier(s).
///
/// Models are named `BirdClassifier_<REGION>.mlmodel`. V1 ships the AU model
/// bundled; NZ/GB/US are delivered as a download at runtime from Firebase
/// Storage (not shown here — see `scripts/train-model/README.md`).
///
/// The model emits `VNClassificationObservation` results where `identifier`
/// is the species' eBird code.
@MainActor
final class MLClassifier {
    enum ClassifierError: Error {
        case modelUnavailable(region: Region)
        case imageConversionFailed
        case visionFailed(underlying: Error)
    }

    private var cachedModels: [Region: VNCoreMLModel] = [:]
    private let topN: Int = 5

    func classify(image: UIImage, region: Region) async throws -> [Prediction] {
        let model = try loadModel(region: region)
        guard let cgImage = image.cgImage else {
            throw ClassifierError.imageConversionFailed
        }

        let topN = self.topN
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error {
                    continuation.resume(throwing: ClassifierError.visionFailed(underlying: error))
                    return
                }
                let results = (request.results as? [VNClassificationObservation]) ?? []
                let top = results.prefix(topN).map {
                    Prediction(
                        speciesCode: $0.identifier,
                        commonName: "",   // filled in by caller from SpeciesRepository
                        confidence: Double($0.confidence)
                    )
                }
                continuation.resume(returning: Array(top))
            }
            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: image.cgImageOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: ClassifierError.visionFailed(underlying: error))
                }
            }
        }
    }

    private func loadModel(region: Region) throws -> VNCoreMLModel {
        if let cached = cachedModels[region] { return cached }
        let resourceName = "BirdClassifier_\(region.rawValue)"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "mlmodel") else {
            throw ClassifierError.modelUnavailable(region: region)
        }
        let coreML = try MLModel(contentsOf: url)
        let visionModel = try VNCoreMLModel(for: coreML)
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
