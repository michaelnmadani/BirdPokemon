import Foundation

struct Prediction: Identifiable, Hashable {
    let id = UUID()
    let speciesCode: String
    let commonName: String
    let confidence: Double

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }

    var displayName: String {
        commonName.isEmpty ? speciesCode : commonName
    }

    /// A species the user picked themselves (no model involved).
    static func manual(_ species: Species) -> Prediction {
        Prediction(speciesCode: species.ebirdCode, commonName: species.commonName, confidence: 0)
    }

    static func ranked(_ predictions: [Prediction], topN: Int = 5) -> [Prediction] {
        Array(predictions.sorted(by: { $0.confidence > $1.confidence }).prefix(topN))
    }
}

enum PredictionDecision: Equatable {
    case highConfidence(Prediction)
    case ambiguous(top: [Prediction])

    static func decide(from predictions: [Prediction]) -> PredictionDecision {
        let ranked = Prediction.ranked(predictions)
        guard let top = ranked.first else {
            return .ambiguous(top: [])
        }
        let second = ranked.dropFirst().first
        let margin = top.confidence - (second?.confidence ?? 0)
        if top.confidence >= 0.85 && margin >= 0.15 {
            return .highConfidence(top)
        }
        return .ambiguous(top: ranked)
    }
}
