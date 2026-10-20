import SwiftUI
import CoreLocation

struct SightingConfirmView: View {
    let photo: CapturedPhoto
    let species: Species
    let prediction: Prediction
    let mlTopPrediction: Prediction?
    /// Called with the saved sighting and whether it's the first of its species.
    let onSaved: (Sighting, Bool) -> Void

    @EnvironmentObject private var store: SightingStore
    @EnvironmentObject private var location: LocationService

    private enum LocationState {
        case locating
        case found(CLLocationCoordinate2D, accuracy: Double?, source: Sighting.LocationSource)
        case unavailable(String)
        case notRequested
    }

    @State private var locationState: LocationState = .notRequested
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Section("Species") {
                LabeledContent("Common name", value: species.commonName)
                LabeledContent("Scientific name") {
                    Text(species.scientificName).italic()
                }
                if prediction.confidence > 0 {
                    LabeledContent("Model confidence", value: "\(prediction.confidencePercent)%")
                }
                if store.isCaptured(species) {
                    Label("Already in your collection", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                } else {
                    Label("New for your collection!", systemImage: "sparkles")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section("When") {
                LabeledContent("Taken", value: capturedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section {
                locationRow
            } header: {
                Text("Where")
            } footer: {
                Text("Locations are only stored with your sightings and never shared.")
            }

            Section("Notes") {
                TextField("What was the bird doing?", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Save sighting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .overlay {
            if isSaving { LoadingView(message: "Saving sighting…") }
        }
        .task {
            if let coordinate = photo.coordinate {
                locationState = .found(coordinate, accuracy: nil, source: .photo)
            } else if photo.source == .camera {
                await locateDevice()
            }
        }
    }

    private var capturedAt: Date {
        photo.takenAt ?? Date()
    }

    @ViewBuilder
    private var locationRow: some View {
        switch locationState {
        case .locating:
            HStack {
                ProgressView()
                Text("Getting your location…").foregroundStyle(.secondary)
            }
        case .found(let coordinate, let accuracy, let source):
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.body.monospacedDigit())
                Text(sourceDescription(source, accuracy: accuracy))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Remove location", role: .destructive) {
                locationState = .notRequested
            }
        case .unavailable(let message):
            Text(message).foregroundStyle(.secondary)
            Button("Try again") { Task { await locateDevice() } }
        case .notRequested:
            Text(photo.source == .library
                 ? "This photo has no location. Add your current location if you took it here."
                 : "No location will be saved.")
                .foregroundStyle(.secondary)
            Button("Use my current location") { Task { await locateDevice() } }
        }
    }

    private func sourceDescription(_ source: Sighting.LocationSource, accuracy: Double?) -> String {
        switch source {
        case .photo:
            return "From the photo"
        case .device:
            if let accuracy { return "Your location, ±\(Int(accuracy.rounded())) m" }
            return "Your location"
        }
    }

    private func locateDevice() async {
        locationState = .locating
        do {
            let fix = try await location.currentLocation()
            locationState = .found(fix.coordinate, accuracy: fix.horizontalAccuracy, source: .device)
        } catch {
            locationState = .unavailable(error.localizedDescription)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        var draft = SightingDraft(
            species: species,
            photo: photo,
            capturedAt: capturedAt,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            mlTopPrediction: mlTopPrediction
        )
        if case .found(let coordinate, let accuracy, let source) = locationState {
            draft.coordinate = coordinate
            draft.locationAccuracy = accuracy
            draft.locationSource = source
        }

        let isNew = !store.isCaptured(species)
        do {
            let sighting = try await store.add(draft)
            onSaved(sighting, isNew)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
