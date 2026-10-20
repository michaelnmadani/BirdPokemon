import SwiftUI
import MapKit

struct SightingsMapView: View {
    @EnvironmentObject private var store: SightingStore
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?

    private var located: [Sighting] {
        store.sightings.filter { $0.coordinate != nil }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedID) {
                ForEach(located) { sighting in
                    // `located` only holds sightings with a coordinate.
                    Marker(sighting.speciesCommonName, systemImage: "bird.fill", coordinate: sighting.coordinate!)
                        .tag(sighting.id)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if located.isEmpty {
                    Text(store.sightings.isEmpty
                         ? "Your sightings will appear here."
                         : "None of your sightings have a location yet.")
                        .font(.footnote)
                        .padding(12)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
            }
            .onChange(of: located.count) { _, _ in
                position = .automatic
            }
            .sheet(item: selectedSighting) { sighting in
                NavigationStack {
                    SightingDetailView(sightingID: sighting.id)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var selectedSighting: Binding<Sighting?> {
        Binding(
            get: { selectedID.flatMap { id in store.sightings.first { $0.id == id } } },
            set: { selectedID = $0?.id }
        )
    }
}
