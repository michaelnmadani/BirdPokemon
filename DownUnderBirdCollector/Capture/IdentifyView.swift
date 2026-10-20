import SwiftUI

/// Shows the photo and either the model's suggestions or, when no model is
/// installed, a prompt to choose the species by hand.
struct IdentifyView: View {
    let photo: CapturedPhoto
    @ObservedObject var viewModel: IdentifyViewModel
    let onChoose: (Prediction) -> Void
    let onPickManually: () -> Void
    let onDiscard: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                content
            }
            .padding(.vertical)
        }
        .navigationTitle("Identify")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive, action: onDiscard)
            }
        }
        .task(id: photo.id) {
            await viewModel.classify(photo, region: appState.selectedRegion, catalog: catalog)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .classifying:
            ProgressView("Identifying the bird…")
                .padding()

        case .noModel:
            VStack(spacing: 12) {
                Text("Which bird did you see?")
                    .font(.title3.bold())
                Text("Automatic identification isn't installed in this version yet, so choose the species from the field guide.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                chooseButton(prominent: true)
            }
            .padding(.horizontal)

        case .done(.highConfidence(let prediction)):
            VStack(spacing: 14) {
                Text("We think this is a")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(prediction.displayName)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                ConfidenceBarView(percent: prediction.confidencePercent)
                    .frame(maxWidth: 260)

                Button {
                    onChoose(prediction)
                } label: {
                    Label("Yes, collect it!", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button("It's a different bird", action: onPickManually)
                    .font(.footnote)
            }

        case .done(.ambiguous(let predictions)):
            VStack(alignment: .leading, spacing: 12) {
                Text(predictions.isEmpty ? "We couldn't recognise this bird" : "Which bird is it?")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(predictions) { prediction in
                    Button {
                        onChoose(prediction)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prediction.displayName)
                                    .font(.body.weight(.medium))
                                ConfidenceBarView(percent: prediction.confidencePercent)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }

                chooseButton(prominent: predictions.isEmpty)
                    .padding(.horizontal)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                chooseButton(prominent: true)
                Button("Try another photo", action: onDiscard)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func chooseButton(prominent: Bool) -> some View {
        let label = Label("Choose species", systemImage: "magnifyingglass")
            .frame(maxWidth: .infinity, minHeight: 50)
        if prominent {
            Button(action: onPickManually) { label }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: onPickManually) { label }
                .buttonStyle(.bordered)
        }
    }
}
