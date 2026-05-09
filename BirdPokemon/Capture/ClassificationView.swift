import SwiftUI

struct ClassificationView: View {
    let image: UIImage
    let region: Region
    @ObservedObject var locationService: LocationService
    var onDiscard: () -> Void

    @StateObject private var viewModel = ClassificationViewModel()
    @State private var confirmPrediction: Prediction?
    @State private var forceAmbiguous = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                switch viewModel.state {
                case .idle, .classifying:
                    ProgressView("Identifying the bird…")
                        .padding()

                case .done(let decision, let enriched):
                    resultContent(decision: forceAmbiguous ? .ambiguous(top: enriched) : decision,
                                  enriched: enriched)

                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Try another photo", action: onDiscard)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Identify")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", action: onDiscard)
            }
        }
        .task {
            await viewModel.classify(image: image, region: region)
        }
        .sheet(item: $confirmPrediction) { prediction in
            SightingConfirmView(
                image: image,
                prediction: prediction,
                mlTopPrediction: topPrediction,
                locationService: locationService,
                onSaved: { onDiscard() }
            )
        }
    }

    private var topPrediction: Prediction? {
        if case .done(_, let enriched) = viewModel.state {
            return enriched.first
        }
        return nil
    }

    @ViewBuilder
    private func resultContent(decision: PredictionDecision, enriched: [Prediction]) -> some View {
        switch decision {
        case .highConfidence(let prediction):
            VStack(spacing: 14) {
                Text("We think this is a")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(prediction.commonName)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                ConfidenceBarView(percent: prediction.confidencePercent)
                    .frame(maxWidth: 260)

                Button {
                    confirmPrediction = prediction
                } label: {
                    Label("Yes, capture it!", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button("It's a different bird") {
                    forceAmbiguous = true
                }
                .font(.footnote)
            }
            .padding(.vertical)

        case .ambiguous(let predictions):
            VStack(alignment: .leading, spacing: 12) {
                Text("Which bird is it?")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(predictions.isEmpty ? enriched : predictions) { prediction in
                    Button {
                        confirmPrediction = prediction
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prediction.commonName.isEmpty ? prediction.speciesCode
                                                                   : prediction.commonName)
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

                NavigationLink {
                    CatalogView(picker: .init { species in
                        confirmPrediction = Prediction(
                            speciesCode: species.ebirdCode,
                            commonName: species.commonName,
                            confidence: 0
                        )
                    })
                } label: {
                    Label("Search all species", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}
