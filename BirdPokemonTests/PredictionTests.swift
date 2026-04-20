import XCTest
@testable import BirdPokemon

final class PredictionTests: XCTestCase {
    func testHighConfidenceDecision() {
        let decision = PredictionDecision.decide(from: [
            .init(speciesCode: "a", commonName: "A", confidence: 0.95),
            .init(speciesCode: "b", commonName: "B", confidence: 0.2),
        ])
        if case .highConfidence(let p) = decision {
            XCTAssertEqual(p.speciesCode, "a")
        } else {
            XCTFail("Expected high-confidence decision")
        }
    }

    func testLowMarginFallsBackToAmbiguous() {
        let decision = PredictionDecision.decide(from: [
            .init(speciesCode: "a", commonName: "A", confidence: 0.6),
            .init(speciesCode: "b", commonName: "B", confidence: 0.55),
        ])
        if case .ambiguous(let top) = decision {
            XCTAssertEqual(top.count, 2)
        } else {
            XCTFail("Expected ambiguous decision")
        }
    }

    func testRankedTakesTopFive() {
        let items = (1...10).map {
            Prediction(speciesCode: "s\($0)", commonName: "S\($0)", confidence: Double($0) / 10)
        }
        let ranked = Prediction.ranked(items)
        XCTAssertEqual(ranked.count, 5)
        XCTAssertEqual(ranked.first?.speciesCode, "s10")
    }
}
