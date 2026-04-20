import Foundation
import UIKit

@MainActor
final class ClassificationViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case classifying
        case done(decision: PredictionDecision, enriched: [Prediction])
        case failed(message: String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.classifying, .classifying): return true
            case (.failed(let a), .failed(let b)): return a == b
            case (.done(_, let a), .done(_, let b)): return a == b
            default: return false
            }
        }
    }

    @Published var state: State = .idle

    private let classifier = MLClassifier()
    private let speciesRepo = SpeciesRepository.shared

    func classify(image: UIImage, region: Region) async {
        state = .classifying
        do {
            let raw = try await classifier.classify(image: image, region: region)
            let enriched = await enrich(predictions: raw)
            let decision = PredictionDecision.decide(from: enriched)
            state = .done(decision: decision, enriched: enriched)
        } catch MLClassifier.ClassifierError.modelUnavailable {
            state = .failed(
                message: "No ML model is bundled for \(region.displayName) yet. Pick a species manually from the catalog."
            )
        } catch {
            state = .failed(message: "Couldn't identify that photo: \(error.localizedDescription)")
        }
    }

    private func enrich(predictions: [Prediction]) async -> [Prediction] {
        var out: [Prediction] = []
        for pred in predictions {
            if let species = await speciesRepo.species(for: pred.speciesCode) {
                out.append(Prediction(
                    speciesCode: species.ebirdCode,
                    commonName: species.commonName,
                    confidence: pred.confidence
                ))
            } else {
                out.append(pred)
            }
        }
        return out
    }
}
