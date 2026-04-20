import Foundation
import UIKit
import CoreLocation

@MainActor
final class SightingConfirmViewModel: ObservableObject {
    @Published var notes: String = ""
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var saved: Bool = false

    let image: UIImage
    let species: Prediction
    let mlTopPrediction: Prediction?

    private let sightingsRepo = SightingsRepository()
    private let userRepo = UserRepository()
    private let uploader = PhotoUploader()
    private let speciesRepo = SpeciesRepository.shared

    init(image: UIImage, species: Prediction, mlTopPrediction: Prediction?) {
        self.image = image
        self.species = species
        self.mlTopPrediction = mlTopPrediction
    }

    func save(uid: String, location: CLLocation?) async {
        isSaving = true
        defer { isSaving = false }

        do {
            let upload = try await uploader.upload(image: image, uid: uid)
            let speciesDoc = await speciesRepo.species(for: species.speciesCode)

            let overrode: Bool = {
                guard let top = mlTopPrediction else { return false }
                return top.speciesCode != species.speciesCode
            }()

            let sighting = Sighting(
                documentID: nil,
                userId: uid,
                speciesCode: species.speciesCode,
                speciesCommonName: speciesDoc?.commonName ?? species.commonName,
                speciesSciName: speciesDoc?.scientificName ?? "",
                photoURL: upload.downloadURL.absoluteString,
                photoStoragePath: upload.storagePath,
                thumbnailURL: nil,
                latitude: location?.coordinate.latitude ?? 0,
                longitude: location?.coordinate.longitude ?? 0,
                geohash: nil,
                locationName: nil,
                capturedAt: Date(),
                notes: notes.isEmpty ? nil : notes,
                mlTopPrediction: mlTopPrediction?.speciesCode,
                mlTopConfidence: mlTopPrediction?.confidence,
                userOverrode: overrode,
                createdAt: nil
            )

            _ = try await sightingsRepo.create(sighting)
            try await userRepo.addCapturedSpecies(uid: uid, speciesCode: species.speciesCode)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
