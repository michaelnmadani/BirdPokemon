import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CollectionViewModel()
    @StateObject private var filterState = FilterState()
    @State private var showSignOutConfirm = false

    private let gridColumns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                FilterBarView(state: filterState)
                    .padding(.vertical, 6)
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(filteredEntries) { species in
                            NavigationLink(value: species) {
                                CollectionCell(species: species, isCaptured: isCaptured(species))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Region") {
                            ForEach(Region.allCases) { region in
                                Button {
                                    Task { await appState.updateHomeRegion(region) }
                                } label: {
                                    Label("\(region.flag) \(region.displayName)",
                                          systemImage: appState.selectedRegion == region ? "checkmark" : "")
                                }
                            }
                        }
                        Section {
                            Button(role: .destructive) {
                                showSignOutConfirm = true
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    } label: {
                        Text("\(appState.selectedRegion.flag) \(appState.selectedRegion.rawValue)")
                    }
                }
            }
            .navigationDestination(for: Species.self) { species in
                SpeciesDetailView(species: species)
            }
            .sheet(isPresented: $filterState.showFilterSheet) {
                FilterSheetView(state: filterState,
                                availableFamilies: Array(Set(viewModel.regionSpecies.map(\.family))).sorted())
            }
            .task { await viewModel.load(region: appState.selectedRegion) }
            .onChange(of: appState.selectedRegion) { _, newRegion in
                Task { await viewModel.load(region: newRegion) }
            }
            .overlay {
                if viewModel.isLoading && viewModel.regionSpecies.isEmpty {
                    LoadingView(message: "Loading collection…")
                }
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { appState.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign back in to access your collection.")
            }
        }
    }

    private var capturedSet: Set<String> {
        Set(appState.currentUser?.capturedSpeciesCodes ?? [])
    }

    private var filteredEntries: [Species] {
        viewModel.entries(filters: filterState.criteria)
    }

    private var header: some View {
        let progress = viewModel.progress(captured: capturedSet)
        return VStack(spacing: 4) {
            Text("\(progress.have) of \(progress.total) captured")
                .font(.headline)
            ProgressView(value: Double(progress.have),
                         total: Double(max(progress.total, 1)))
                .progressViewStyle(.linear)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func isCaptured(_ species: Species) -> Bool {
        capturedSet.contains(species.ebirdCode)
    }
}

private struct CollectionCell: View {
    let species: Species
    let isCaptured: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                AsyncRemoteImage(url: species.thumbnailURL.flatMap(URL.init(string:)))
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !isCaptured {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.6))
                    Image(systemName: "questionmark")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            Text(species.commonName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(isCaptured ? .primary : .secondary)
        }
    }
}
