import SwiftUI

struct SightingsListView: View {
    @EnvironmentObject private var store: SightingStore

    var body: some View {
        NavigationStack {
            Group {
                if store.sightings.isEmpty && !store.isLoading {
                    EmptyStateView(
                        systemImage: "bird",
                        title: "No sightings yet",
                        message: "Capture your first bird to start your collection."
                    )
                } else {
                    List {
                        if let error = store.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        ForEach(store.sightings) { sighting in
                            NavigationLink(value: sighting.id) {
                                SightingRowView(sighting: sighting)
                            }
                        }
                        .onDelete { offsets in
                            // Resolve ids before awaiting: the list changes as deletes land.
                            let ids = offsets.map { store.sightings[$0].id }
                            Task { await store.delete(ids: ids) }
                        }
                    }
                }
            }
            .overlay {
                if store.isLoading && store.sightings.isEmpty {
                    LoadingView(message: "Loading sightings…")
                }
            }
            .navigationTitle("Sightings")
            .navigationDestination(for: String.self) { id in
                SightingDetailView(sightingID: id)
            }
        }
    }
}
