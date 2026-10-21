import SwiftUI

/// The collector's album: one card per species in the region. Collected
/// species show your own photo; the rest show the field guide photo in
/// greyscale until you find them. Can be grouped and resized.
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
    @AppStorage("collection.groupBy") private var grouping: CollectionGrouping = .none
    @AppStorage("collection.gridSize") private var gridSize: CollectionGridSize = .medium

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: gridSize.minimumWidth), spacing: gridSize == .small ? 8 : 12)]
    }

    private var sections: [CollectionSection] {
        let groups = grouping == .group ? catalog.groups(in: appState.selectedRegion) : []
        return CollectionSections.build(entries, by: grouping, groups: groups)
    }

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

                    gridOptions

                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(entries.isEmpty ? [] : sections) { section in
                            Section {
                                ForEach(section.species) { species in
                                    NavigationLink(value: species) {
                                        CollectionCell(
                                            species: species,
                                            isCaptured: store.isCaptured(species),
                                            myPhoto: store.latestSighting(of: species.ebirdCode).flatMap(store.thumbnailURL(for:)),
                                            compact: gridSize == .small
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                if section.title != nil { sectionHeader(section) }
                            }
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

    private var gridOptions: some View {
        HStack {
            Menu {
                Picker("Group by", selection: $grouping) {
                    ForEach(CollectionGrouping.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Label(grouping == .none ? "Group by" : "Grouped by \(grouping.label.lowercased())",
                      systemImage: "square.grid.3x1.below.line.grid.1x2")
                    .font(.subheadline)
            }
            Spacer()
            Picker("Picture size", selection: $gridSize) {
                ForEach(CollectionGridSize.allCases) { size in
                    Text(size.label).tag(size).accessibilityLabel("\(size.rawValue) pictures")
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal)
    }

    private func sectionHeader(_ section: CollectionSection) -> some View {
        let have = section.species.filter(store.isCaptured).count
        return HStack(spacing: 8) {
            if let emoji = section.emoji { Text(emoji) }
            if let swatch = section.swatch {
                Circle()
                    .fill(swatch.swiftUIColor)
                    .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    .frame(width: 14, height: 14)
            }
            Text(section.title ?? "").font(.headline)
            Spacer()
            Text("\(have) / \(section.species.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
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
    var compact = false

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // Not collected yet: the field guide photo in greyscale.
                    AsyncRemoteImage(url: isCaptured ? (myPhoto ?? species.thumbnail) : species.thumbnail)
                        .grayscale(isCaptured ? 0 : 1)
                        .opacity(isCaptured ? 1 : 0.85)
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12))
                .overlay(alignment: .topTrailing) {
                    Group {
                        if isCaptured {
                            CapturedBadgeView()
                        } else {
                            Image(systemName: "questionmark")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.black.opacity(0.55)))
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        }
                    }
                    .scaleEffect(compact ? 0.8 : 1)
                    .padding(compact ? 3 : 6)
                }

            Text(species.commonName)
                .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(isCaptured ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(species.commonName)
        .accessibilityValue(isCaptured ? "Collected" : "Not collected yet")
    }
}
