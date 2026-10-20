import Foundation

/// One BirdNET class, from a "Dacelo novaeguineae_Laughing Kookaburra" label.
struct SoundLabel: Equatable {
    let scientificName: String
    let commonName: String
    /// Non-bird classes ("Engine_Engine", "Dog_Dog") repeat the same name.
    let isBird: Bool
}

/// A class heard in one 3-second window.
struct SoundDetection: Equatable {
    let index: Int
    let confidence: Double
}

/// Everything heard of one class during a listening session.
struct SoundTallyEntry: Equatable {
    let index: Int
    var best: Double
    var count: Int
    var firstAt: Double
    var lastAt: Double
}

/// Pure helpers for BirdNET sound identification, so they can be unit tested
/// without the model. Mirrors `web/src/js/soundid-core.js`.
enum SoundIDCore {
    static let sampleRate = 48_000.0
    /// BirdNET V2.4 listens to 3-second chunks.
    static let window = 144_000
    /// BirdNET's own default threshold.
    static let minConfidence = 0.25

    static func parseLabels(_ text: String) -> [SoundLabel] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "_", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let sci = parts.first, !sci.isEmpty else { return nil }
            let common = parts.count > 1 ? parts[1] : sci
            return SoundLabel(scientificName: sci, commonName: common, isBird: sci != common)
        }
    }

    /// For each class, the matching field-guide species code — by scientific
    /// name, then by common name where the taxonomies differ — or nil.
    static func mapLabels(_ labels: [SoundLabel], to species: [Species]) -> [String?] {
        var bySci: [String: String] = [:]
        var byCommon: [String: String] = [:]
        for s in species {
            bySci[s.scientificName.lowercased()] = s.ebirdCode
            byCommon[s.commonName.lowercased()] = s.ebirdCode
        }
        return labels.map { label in
            guard label.isBird else { return nil }
            return bySci[label.scientificName.lowercased()] ?? byCommon[label.commonName.lowercased()]
        }
    }

    /// BirdNET's flat sigmoid: logits → confidences in 0…1.
    static func sigmoid(_ x: Float) -> Double {
        1 / (1 + exp(-Double(min(15, max(-15, x)))))
    }

    /// Classes at or above `min` in one window, best first.
    static func detections(_ logits: [Float], min: Double = minConfidence, allowed: (Int) -> Bool = { _ in true }) -> [SoundDetection] {
        logits.indices
            .filter(allowed)
            .map { SoundDetection(index: $0, confidence: sigmoid(logits[$0])) }
            .filter { $0.confidence >= min }
            .sorted { $0.confidence > $1.confidence }
    }

    static func mixToMono(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        if channels.count == 1 { return first }
        let scale = 1 / Float(channels.count)
        var out = [Float](repeating: 0, count: first.count)
        for channel in channels {
            for i in 0..<min(out.count, channel.count) { out[i] += channel[i] * scale }
        }
        return out
    }

    /// Linear-interpolation resample to 48 kHz.
    static func resample(_ samples: [Float], from rate: Double, to target: Double = sampleRate) -> [Float] {
        guard rate != target, !samples.isEmpty else { return samples }
        let ratio = rate / target
        let count = Int(Double(samples.count) / ratio)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Double(i) * ratio
            let j = Int(pos)
            let frac = Float(pos - Double(j))
            let next = j + 1 < samples.count ? samples[j + 1] : samples[j]
            out[i] = samples[j] * (1 - frac) + next * frac
        }
        return out
    }

    /// 3-second windows with their start sample; a tail of at least 1 s is zero-padded.
    static func windows(_ samples: [Float], size: Int = window) -> [(start: Int, samples: [Float])] {
        stride(from: 0, to: samples.count, by: size).compactMap { start in
            let end = min(start + size, samples.count)
            var chunk = Array(samples[start..<end])
            if chunk.count == size { return (start: start, samples: chunk) }
            guard chunk.count >= Int(sampleRate) else { return nil }
            chunk.append(contentsOf: repeatElement(0, count: size - chunk.count))
            return (start: start, samples: chunk)
        }
    }

    static func addToTally(_ tally: inout [Int: SoundTallyEntry], _ found: [SoundDetection], at seconds: Double) {
        for d in found {
            var entry = tally[d.index] ?? SoundTallyEntry(index: d.index, best: 0, count: 0, firstAt: seconds, lastAt: seconds)
            entry.best = max(entry.best, d.confidence)
            entry.count += 1
            entry.lastAt = seconds
            tally[d.index] = entry
        }
    }

    static func rank(_ tally: [Int: SoundTallyEntry]) -> [SoundTallyEntry] {
        tally.values.sorted { ($0.best, $0.count, -$0.index) > ($1.best, $1.count, -$1.index) }
    }
}
