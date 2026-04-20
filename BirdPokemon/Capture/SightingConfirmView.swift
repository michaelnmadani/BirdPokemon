import SwiftUI
import CoreLocation

struct SightingConfirmView: View {
    let image: UIImage
    let prediction: Prediction
    let mlTopPrediction: Prediction?
    @ObservedObject var locationService: LocationService
    var onSaved: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SightingConfirmViewModel

    init(image: UIImage,
         prediction: Prediction,
         mlTopPrediction: Prediction?,
         locationService: LocationService,
         onSaved: @escaping () -> Void) {
        self.image = image
        self.prediction = prediction
        self.mlTopPrediction = mlTopPrediction
        self.locationService = locationService
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: SightingConfirmViewModel(
            image: image,
            species: prediction,
            mlTopPrediction: mlTopPrediction
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Section("Species") {
                    LabeledContent("Common name", value: prediction.commonName.isEmpty
                                    ? prediction.speciesCode : prediction.commonName)
                    if prediction.confidence > 0 {
                        LabeledContent("Model confidence", value: "\(prediction.confidencePercent)%")
                    }
                }

                Section("Location") {
                    if let loc = locationService.lastLocation {
                        LabeledContent("Latitude", value: String(format: "%.5f", loc.coordinate.latitude))
                        LabeledContent("Longitude", value: String(format: "%.5f", loc.coordinate.longitude))
                    } else {
                        Text("Waiting for GPS fix…")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("What was the bird doing?", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Save sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .overlay {
                if viewModel.isSaving { LoadingView(message: "Saving sighting…") }
            }
            .task {
                _ = try? await locationService.currentLocation()
            }
            .onChange(of: viewModel.saved) { _, saved in
                if saved {
                    dismiss()
                    onSaved()
                }
            }
        }
    }

    private func save() async {
        guard let uid = appState.currentUser?.uid else {
            viewModel.errorMessage = "You're signed out."
            return
        }
        await viewModel.save(uid: uid, location: locationService.lastLocation)
    }
}
