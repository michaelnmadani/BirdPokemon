import SwiftUI

/// The collector's album: one card per species in the region. Collected
/// species show your own photo; the rest stay hidden until you find them.
struct CollectionView: View {
    enum Show: String, CaseIterable, Identifiable {
        case all = "All"
        case collected = "Collected"
        case missing = "To find"
        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore
    @StateObject private var filterState = FilterState()
    @State private var show: Show = .all
    @State private var showSettings = false

    private let gridColumns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    private var regionSpecies: [Species] {
        catalog.species(in: appState.selectedRegion)
    }

    private var entries: [Species] {
        regionSpecies.filter { species in
            guard filterState.criteria.matches(species) else { return false }
            switch show {
            case .all: return true
            case .collected: return store.isCaptured(species)
            case .missing: return !store.isCaptured(species)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header
                    Picker("Show", selection: $show) {
                        ForEach(Show.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    FilterBarView(state: filterState, resultCount: entries.count)

                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(entries) { species in
                            NavigationLink(value: species) {
                                CollectionCell(
                                    species: species,
                                    isCaptured: store.isCaptured(species),
                                    myPhoto: store.latestSighting(of: species.ebirdCode).flatMap(store.thumbnailURL(for:))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .searchable(text: $filterState.criteria.searchText, prompt: "Search your collection")
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Species.self) { species in
                SpeciesDetailView(species: species)
            }
            .sheet(isPresented: $filterState.showFilterSheet) {
                FilterSheetView(state: filterState, availableFamilies: FamilyOption.options(for: regionSpecies))
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .overlay {
                if store.isLoading && store.sightings.isEmpty {
                    LoadingView(message: "Loading collection…")
                } else if entries.isEmpty {
                    EmptyStateView(
                        title: show == .collected ? "Nothing collected yet" : "No species match",
                        message: show == .collected ? "Head to Capture and photograph your first bird." : "Try clearing filters."
                    )
                    .padding(.top, 160)
                }
            }
        }
    }

    private var header: some View {
        let have = regionSpecies.filter(store.isCaptured).count
        let total = regionSpecies.count
        return VStack(spacing: 6) {
            Text("\(appState.selectedRegion.flag) \(have) of \(total) collected")
                .font(.headline)
            ProgressView(value: Double(have), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
            if let error = store.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

private struct CollectionCell: View {
    let species: Species
    let isCaptured: Bool
    let myPhoto: URL?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                AsyncRemoteImage(url: isCaptured ? (myPhoto ?? species.thumbnail) : species.thumbnail)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .blur(radius: isCaptured ? 0 : 10)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if isCaptured {
                    CapturedBadgeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.55))
                    Image(systemName: "questionmark")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 104)

            Text(species.commonName)
                .font(.caption.weight(.medium))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(isCaptured ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(species.commonName)
        .accessibilityValue(isCaptured ? "Collected" : "Not collected yet")
    }
}
