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
    /// The photo identifier's best guess wasn't a field-guide bird, so it may
    /// not know this one: suggestions are shown as "possible matches".
    @Published private(set) var unsure = false

    private let classifier = MLClassifier()
    /// The bundled iNaturalist bird model, loaded once.
    private static var photoIdentifier: PhotoIdentifier?

    /// The model's best guess, recorded on the sighting so we can measure
    /// how often people override it.
    var topPrediction: Prediction? { predictions.first }

    func classify(_ photo: CapturedPhoto, region: Region, catalog: SpeciesCatalog) async {
        predictions = []
        unsure = false
        // A region-specific Core ML model (scripts/train-model) wins when bundled.
        guard MLClassifier.isModelAvailable(for: region) else {
            guard PhotoIdentifier.isAvailable else {
                state = .noModel
                return
            }
            await suggest(photo, species: catalog.species(in: region), catalog: catalog)
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

    private func suggest(_ photo: CapturedPhoto, species: [Species], catalog: SpeciesCatalog) async {
        state = .classifying
        do {
            let identifier: PhotoIdentifier
            if let loaded = Self.photoIdentifier {
                identifier = loaded
            } else {
                identifier = try await Task.detached(priority: .userInitiated) { try PhotoIdentifier(species: species) }.value
                Self.photoIdentifier = identifier
            }
            let result = try await identifier.identify(photo.image)
            predictions = result.suggestions.compactMap { suggestion in
                catalog.species(code: suggestion.code).map {
                    Prediction(speciesCode: $0.ebirdCode, commonName: $0.commonName, confidence: suggestion.confidence)
                }
            }
            unsure = result.unsure
            // Never claim a confident match when the model's real best guess is a foreign bird.
            state = .done(unsure ? .ambiguous(top: predictions) : PredictionDecision.decide(from: predictions))
        } catch {
            state = .failed(message: "Couldn't identify that photo: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
        predictions = []
        unsure = false
    }
}
