import SwiftUI

struct SpeciesDetailView: View {
    let species: Species

    @EnvironmentObject private var store: SightingStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    /// nil follows the Settings choice; the button flips between painting and photo.
    @State private var showPainting: Bool?

    private var mySightings: [Sighting] {
        store.sightings(of: species.ebirdCode)
    }

    /// The watercolour (if there is one and it's chosen) or the photo, with its
    /// credit; a watercolour can be flipped to the photo it was painted from.
    @ViewBuilder
    private var heroPicture: some View {
        let artwork = catalog.artwork(for: species)
        let painting = artwork != nil && (showPainting ?? (catalog.pictureStyle == .watercolour))
        VStack(alignment: .trailing, spacing: 4) {
            AsyncRemoteImage(url: painting ? artwork?.url : species.thumbnail)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Spacer(minLength: 0)
                if painting, let artwork {
                    Text(artwork.art.credit)
                } else if let credit = species.photoCredit {
                    Text("Photo: \(credit) via iNaturalist")
                }
                if artwork != nil {
                    Button(painting ? "Show photo" : "Show watercolour") { showPainting = !painting }
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroPicture

                VStack(alignment: .leading, spacing: 8) {
                    Text(species.commonName)
                        .font(.largeTitle.bold())
                    Text(species.scientificName)
                        .italic()
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        if store.isCaptured(species) {
                            Label("Collected", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Text("\(species.sizeCategory.displayName) · \(species.sizeCategory.approxLength)")
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
                                    .accessibilityLabel(color.displayName)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                CallPlayerView(species: species)
                    .padding(.horizontal)

                let groups = catalog.groups(containing: species.ebirdCode, in: appState.selectedRegion)
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups) { group in
                                NavigationLink {
                                    GroupDetailView(group: group)
                                } label: {
                                    Text(group.kind == .genus ? "\(group.name) (\(group.genus ?? ""))" : group.title)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(.secondarySystemBackground), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Taxonomy").font(.headline)
                    LabeledContent("Family", value: species.familyDisplayName)
                    LabeledContent("Order", value: species.order)
                    LabeledContent("Regions", value: species.regions.map(\.flag).joined(separator: " "))
                }
                .padding(.horizontal)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your sightings").font(.headline)
                    if mySightings.isEmpty {
                        Text("You haven't collected one yet — go find it!")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(mySightings) { sighting in
                            NavigationLink {
                                SightingDetailView(sightingID: sighting.id)
                            } label: {
                                SightingRowView(sighting: sighting)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    if let url = URL(string: species.ebirdURL) {
                        Link(destination: url) {
                            Label("Read more on eBird", systemImage: "arrow.up.right.square")
                        }
                    }
                    if let url = species.wikipediaURL.flatMap(URL.init(string:)) {
                        Link(destination: url) {
                            Label("Wikipedia", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
