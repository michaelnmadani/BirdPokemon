import Foundation
import UIKit
import Vision
import CoreML

/// Wraps the region-specific Core ML image classifier.
///
/// V1 ships the AU model bundled. NZ / GB / US models are fetched from
/// Firebase Storage on first use of that region — see `ModelRepository`.
///
/// The model emits `VNClassificationObservation` results where `identifier`
/// is the species' eBird code.
@MainActor
final class MLClassifier {
    enum ClassifierError: Error {
        case modelUnavailable(region: Region, underlying: Error?)
        case imageConversionFailed
        case visionFailed(underlying: Error)
    }

    private var cachedModels: [Region: VNCoreMLModel] = [:]
    private let topN: Int = 5
    private let modelRepository: ModelRepository

    init(modelRepository: ModelRepository = .shared) {
        self.modelRepository = modelRepository
    }

    /// Ensures the classifier for `region` is loaded (downloading + compiling
    /// if necessary). Safe to call on app launch or ahead of a capture to
    /// prime the cache.
    func prepareModel(region: Region) async throws {
        _ = try await loadModel(region: region)
    }

    func classify(image: UIImage, region: Region) async throws -> [Prediction] {
        let model = try await loadModel(region: region)
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

    private func loadModel(region: Region) async throws -> VNCoreMLModel {
        if let cached = cachedModels[region] { return cached }
        do {
            let url = try await modelRepository.compiledModelURL(for: region)
            let coreML = try MLModel(contentsOf: url)
            let visionModel = try VNCoreMLModel(for: coreML)
            cachedModels[region] = visionModel
            return visionModel
        } catch {
            throw ClassifierError.modelUnavailable(region: region, underlying: error)
        }
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
