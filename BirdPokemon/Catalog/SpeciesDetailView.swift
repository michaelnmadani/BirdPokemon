import SwiftUI

struct SpeciesDetailView: View {
    let species: Species

    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SpeciesDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncRemoteImage(url: species.thumbnailURL.flatMap(URL.init(string:)))
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    Text(species.commonName)
                        .font(.largeTitle.bold())
                    Text(species.scientificName)
                        .italic()
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        if isCaptured {
                            Label("Captured", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Text(species.sizeCategory.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }

                    if !species.primaryColors.isEmpty {
                        HStack(spacing: 6) {
                            Text("Colours:").font(.caption).foregroundStyle(.secondary)
                            ForEach(species.primaryColors) { color in
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Taxonomy").font(.headline)
                    LabeledContent("Family", value: species.familyCommonName ?? species.family)
                    LabeledContent("Order", value: species.order)
                    LabeledContent("Regions", value: species.regions.map(\.flag).joined(separator: " "))
                }
                .padding(.horizontal)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your sightings").font(.headline)
                    if viewModel.sightings.isEmpty {
                        Text("You haven't caught one yet — go find it!")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.sightings) { sighting in
                            NavigationLink {
                                SightingDetailView(sighting: sighting)
                            } label: {
                                SightingRowView(sighting: sighting)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)

                if let url = URL(string: species.ebirdURL) {
                    Link(destination: url) {
                        Label("Read more on eBird", systemImage: "arrow.up.right.square")
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = appState.currentUser?.uid {
                await viewModel.load(uid: uid, speciesCode: species.ebirdCode)
            }
        }
    }

    private var isCaptured: Bool {
        appState.currentUser?.capturedSpeciesCodes.contains(species.ebirdCode) ?? false
    }
}
