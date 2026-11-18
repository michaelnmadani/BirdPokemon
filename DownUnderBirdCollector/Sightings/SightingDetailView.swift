import SwiftUI
import MapKit

/// Looks the sighting up by id so the screen reflects edits and deletions.
struct SightingDetailView: View {
    let sightingID: String

    @EnvironmentObject private var store: SightingStore
    @EnvironmentObject private var catalog: SpeciesCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var sighting: Sighting? {
        store.sightings.first { $0.id == sightingID }
    }

    static func soundCredit(_ sighting: Sighting) -> String {
        guard let confidence = sighting.mlTopConfidence, confidence > 0 else { return "Identified by sound with BirdNET" }
        return "Identified by sound with BirdNET (\(Int((confidence * 100).rounded()))%)"
    }

    var body: some View {
        Group {
            if let sighting {
                content(sighting)
            } else {
                EmptyStateView(systemImage: "trash", title: "Sighting deleted")
            }
        }
        .navigationTitle(sighting?.speciesCommonName ?? "Sighting")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ sighting: Sighting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photo = store.photoURL(for: sighting) {
                    AsyncRemoteImage(url: photo, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 420)
                } else {
                    AsyncRemoteImage(url: catalog.picture(for: catalog.species(code: sighting.speciesCode)))
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(sighting.speciesCommonName)
                        .font(.largeTitle.bold())
                    Text(sighting.speciesSciName)
                        .italic()
                        .foregroundStyle(.secondary)
                    Text(sighting.capturedAt.formatted(date: .long, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if sighting.identifiedBy == .sound {
                        Label(Self.soundCredit(sighting), systemImage: "waveform")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if store.photoURL(for: sighting) == nil {
                        Label("Logged without a photo", systemImage: "binoculars")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let species = catalog.species(code: sighting.speciesCode) {
                        NavigationLink {
                            SpeciesDetailView(species: species)
                        } label: {
                            Label("Field guide entry", systemImage: "book")
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal)

                if let coordinate = sighting.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Marker(sighting.speciesCommonName, coordinate: coordinate)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    Label("No location was saved for this sighting.", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                if let notes = sighting.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(notes)
                    }
                    .padding(.horizontal)
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete sighting", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
        .confirmationDialog("Delete this sighting?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(ids: [sighting.id])
                    dismiss()
                }
            }
        } message: {
            Text("The photo will be removed too. If it's your only sighting of this species, it leaves your collection.")
        }
    }
}
