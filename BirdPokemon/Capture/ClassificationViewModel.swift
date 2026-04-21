import Foundation
import UIKit

@MainActor
final class ClassificationViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case preparingModel(region: Region, fraction: Double?)
        case classifying
        case done(decision: PredictionDecision, enriched: [Prediction])
        case failed(message: String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.classifying, .classifying): return true
            case (.preparingModel(let r1, let f1), .preparingModel(let r2, let f2)):
                return r1 == r2 && f1 == f2
            case (.failed(let a), .failed(let b)): return a == b
            case (.done(_, let a), .done(_, let b)): return a == b
            default: return false
            }
        }
    }

    @Published var state: State = .idle

    private let classifier = MLClassifier()
    private let speciesRepo = SpeciesRepository.shared
    private var progressObserverID: UUID?

    func classify(image: UIImage, region: Region) async {
        await ensureModelReady(region: region)
        // If model prep failed, `state` will already be `.failed`.
        if case .failed = state { return }

        state = .classifying
        do {
            let raw = try await classifier.classify(image: image, region: region)
            let enriched = await enrich(predictions: raw)
            let decision = PredictionDecision.decide(from: enriched)
            state = .done(decision: decision, enriched: enriched)
        } catch MLClassifier.ClassifierError.modelUnavailable(let region, _) {
            state = .failed(
                message: "Couldn't load the \(region.displayName) model. Check your connection and try again, or pick the bird manually from the catalog."
            )
        } catch {
            state = .failed(message: "Couldn't identify that photo: \(error.localizedDescription)")
        }
    }

    /// Surface download progress by switching to `.preparingModel` while the
    /// region's model is being fetched from Firebase Storage on first use.
    private func ensureModelReady(region: Region) async {
        state = .preparingModel(region: region, fraction: nil)

        let observerID = await ModelRepository.shared.addProgressObserver { [weak self] fraction in
            Task { @MainActor in
                guard let self else { return }
                if case .preparingModel = self.state {
                    self.state = .preparingModel(region: region, fraction: fraction)
                }
            }
        }
        progressObserverID = observerID
        defer {
            if let id = progressObserverID {
                Task { await ModelRepository.shared.removeProgressObserver(id) }
                progressObserverID = nil
            }
        }

        do {
            try await classifier.prepareModel(region: region)
        } catch MLClassifier.ClassifierError.modelUnavailable(let region, _) {
            state = .failed(
                message: "Couldn't load the \(region.displayName) model. Check your connection and try again, or pick the bird manually from the catalog."
            )
        } catch {
            state = .failed(message: "Couldn't prepare the model: \(error.localizedDescription)")
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
