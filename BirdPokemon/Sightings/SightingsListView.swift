import SwiftUI

struct SightingsListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SightingsListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sightings.isEmpty && !viewModel.isLoading {
                    EmptyStateView(
                        systemImage: "bird",
                        title: "No sightings yet",
                        message: "Capture your first bird to start your collection."
                    )
                } else {
                    List {
                        ForEach(viewModel.sightings) { sighting in
                            NavigationLink(value: sighting) {
                                SightingRowView(sighting: sighting)
                            }
                        }
                        .onDelete { offsets in
                            Task {
                                for index in offsets {
                                    await viewModel.delete(viewModel.sightings[index])
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.sightings.isEmpty {
                    LoadingView(message: "Loading sightings…")
                }
            }
            .navigationTitle("Sightings")
            .navigationDestination(for: Sighting.self) { sighting in
                SightingDetailView(sighting: sighting)
            }
            .task {
                if let uid = appState.currentUser?.uid {
                    viewModel.start(uid: uid)
                }
            }
        }
    }
}
