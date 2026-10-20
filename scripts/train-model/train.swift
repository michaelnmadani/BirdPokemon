#!/usr/bin/env swift
// Train BirdClassifier_<REGION>.mlmodel from the folder built by
// scripts/seed-ebird/fetch-inat-images.ts. Runs on macOS with Xcode installed.
//
//   swift scripts/train-model/train.swift AU
//
// Output: DownUnderBirdCollector/Resources/ML/BirdClassifier_AU.mlmodel
// Re-run `xcodegen generate` afterwards so Xcode compiles it into the app.

import CreateML
import Foundation

let region = CommandLine.arguments.dropFirst().first?.uppercased() ?? "AU"
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let trainingDir = repo.appendingPathComponent("scripts/seed-ebird/data/training/\(region)")
let outputDir = repo.appendingPathComponent("DownUnderBirdCollector/Resources/ML")
let outputURL = outputDir.appendingPathComponent("BirdClassifier_\(region).mlmodel")
let minimumImages = 40

guard FileManager.default.fileExists(atPath: trainingDir.path) else {
    print("No training images at \(trainingDir.path). Run: cd scripts/seed-ebird && npm run fetch-images -- --region \(region)")
    exit(1)
}

// Only train on species with enough photos; sparse classes hurt accuracy.
let classes = try FileManager.default.contentsOfDirectory(at: trainingDir, includingPropertiesForKeys: [.isDirectoryKey])
    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
var files: [String: [URL]] = [:]
for dir in classes {
    let images = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
    if images.count >= minimumImages {
        files[dir.lastPathComponent] = images
    } else {
        print("Skipping \(dir.lastPathComponent): only \(images.count) images")
    }
}
print("Training on \(files.count) species, \(files.values.map(\.count).reduce(0, +)) images…")

let parameters = MLImageClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    maxIterations: 40,
    augmentation: [.flip, .crop, .rotation, .exposure],
    algorithm: .transferLearning(featureExtractor: .scenePrint(revision: 2), classifier: .logisticRegressor)
)
let classifier = try MLImageClassifier(trainingData: .filesByLabel(files), parameters: parameters)

let trainingAccuracy = (1 - classifier.trainingMetrics.classificationError) * 100
let validationAccuracy = (1 - classifier.validationMetrics.classificationError) * 100
print(String(format: "Training accuracy %.1f%%, validation accuracy %.1f%%", trainingAccuracy, validationAccuracy))

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let metadata = MLModelMetadata(
    author: "Down Under Bird Collector",
    shortDescription: "Identifies \(files.count) \(region) bird species. Labels are eBird species codes.",
    license: "Trained on CC-licensed iNaturalist photos; see manifest.jsonl for credits.",
    version: "1"
)
try classifier.write(to: outputURL, metadata: metadata)
print("Wrote \(outputURL.path)")
