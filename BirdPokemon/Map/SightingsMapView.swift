import SwiftUI
import MapKit

struct SightingsMapView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SightingsMapViewModel()
    @State private var selected: Sighting?

    var body: some View {
        NavigationStack {
            Map(position: $viewModel.cameraPosition, selection: $selected) {
                ForEach(viewModel.sightings) { sighting in
                    Marker(sighting.speciesCommonName, coordinate: sighting.coordinate)
                        .tag(sighting)
                }
            }
            .navigationTitle("Map")
            .sheet(item: $selected) { sighting in
                NavigationStack {
                    SightingDetailView(sighting: sighting)
                }
                .presentationDetents([.medium, .large])
            }
            .task {
                if let uid = appState.currentUser?.uid {
                    viewModel.start(uid: uid)
                }
            }
        }
    }
}
