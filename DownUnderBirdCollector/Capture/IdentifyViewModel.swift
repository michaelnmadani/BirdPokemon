import Foundation
import UIKit

@MainActor
final class IdentifyViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case classifying
        /// No model bundled for this region: the user picks the species.
        case noModel
        case done(PredictionDecision)
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var predictions: [Prediction] = []

    private let classifier = MLClassifier()

    /// The model's best guess, recorded on the sighting so we can measure
    /// how often people override it.
    var topPrediction: Prediction? { predictions.first }

    func classify(_ photo: CapturedPhoto, region: Region, catalog: SpeciesCatalog) async {
        predictions = []
        guard MLClassifier.isModelAvailable(for: region) else {
            state = .noModel
            return
        }
        state = .classifying
        do {
            let raw = try await classifier.classify(image: photo.image, region: region)
            let enriched = raw.map { prediction in
                guard let species = catalog.species(code: prediction.speciesCode) else { return prediction }
                return Prediction(speciesCode: species.ebirdCode, commonName: species.commonName, confidence: prediction.confidence)
            }
            predictions = Prediction.ranked(enriched)
            state = .done(PredictionDecision.decide(from: predictions))
        } catch {
            state = .failed(message: "Couldn't identify that photo: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
        predictions = []
    }
}
