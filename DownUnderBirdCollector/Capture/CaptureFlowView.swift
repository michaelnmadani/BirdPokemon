import SwiftUI
import PhotosUI

/// Photo → identify (or choose) → confirm → saved, or — for a bird seen or
/// heard but not photographed — choose → confirm → saved. Navigation is driven
/// by an explicit path so finishing a save can reset the whole flow in one step.
struct CaptureFlowView: View {
    private enum Route: Hashable {
        case pickSpecies
        case confirm(speciesCode: String, prediction: Prediction)
    }

    private struct Celebration: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore
    @EnvironmentObject private var location: LocationService

    @StateObject private var identify = IdentifyViewModel()
    @State private var photo: CapturedPhoto?
    @State private var path: [Route] = []
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var celebration: Celebration?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let photo {
                    IdentifyView(
                        photo: photo,
                        viewModel: identify,
                        onChoose: { prediction in
                            path.append(.confirm(speciesCode: prediction.speciesCode, prediction: prediction))
                        },
                        onPickManually: { path.append(.pickSpecies) },
                        onDiscard: reset
                    )
                } else {
                    landing
                }
            }
            .navigationDestination(for: Route.self, destination: destination)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                photo = CapturedPhoto(image: image, source: .camera)
                showCamera = false
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .alert(item: $celebration) { celebration in
            Alert(title: Text(celebration.title), message: Text(celebration.message), dismissButton: .default(Text("Nice!")))
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .pickSpecies:
            SpeciesPickerView(region: appState.selectedRegion) { species in
                path.append(.confirm(speciesCode: species.ebirdCode, prediction: .manual(species)))
            }
        case .confirm(let code, let prediction):
            // `photo` is nil when logging without one.
            if let species = catalog.species(code: code) {
                SightingConfirmView(
                    photo: photo,
                    species: species,
                    prediction: prediction,
                    mlTopPrediction: identify.topPrediction,
                    onSaved: finish
                )
            } else {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unknown species",
                    message: "\(prediction.displayName) isn't in the field guide. Choose the species instead."
                )
            }
        }
    }

    private var landing: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Spot a bird?")
                    .font(.title.bold())
                Text("Photograph it to add it to your collection — or just log it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                if CameraView.isAvailable {
                    Button {
                        location.requestPermissionIfNeeded()
                        showCamera = true
                    } label: {
                        Label("Open camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                }

                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("Pick from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)

                Button {
                    location.requestPermissionIfNeeded()
                    path.append(.pickSpecies)
                } label: {
                    Label("Log without a photo", systemImage: "binoculars")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)

                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)

            Text("\(collectedInRegion) of \(catalog.species(in: appState.selectedRegion).count) species collected")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .navigationTitle("Capture")
        .overlay {
            if isImporting { LoadingView(message: "Opening photo…") }
        }
    }

    private var collectedInRegion: Int {
        catalog.species(in: appState.selectedRegion).filter(store.isCaptured).count
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let picked = CapturedPhoto(libraryData: data) else {
                importError = "That photo couldn't be opened."
                return
            }
            importError = nil
            photo = picked
        } catch {
            importError = error.localizedDescription
        }
    }

    private func finish(_ sighting: Sighting, isNewSpecies: Bool) {
        let total = catalog.species(in: appState.selectedRegion).count
        if isNewSpecies {
            celebration = Celebration(
                title: "New species collected!",
                message: "\(sighting.speciesCommonName) is now in your collection — \(collectedInRegion) of \(total) \(appState.selectedRegion.displayName) species."
            )
        } else {
            celebration = Celebration(
                title: "Sighting saved",
                message: "Another \(sighting.speciesCommonName) for your log."
            )
        }
        reset()
    }

    private func reset() {
        path = []
        photo = nil
        identify.reset()
    }
}
