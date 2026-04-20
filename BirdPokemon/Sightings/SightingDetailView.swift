import SwiftUI
import MapKit

struct SightingDetailView: View {
    let sighting: Sighting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncRemoteImage(url: URL(string: sighting.photoURL))
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(sighting.speciesCommonName)
                        .font(.largeTitle.bold())
                    Text(sighting.speciesSciName)
                        .italic()
                        .foregroundStyle(.secondary)
                    Text(sighting.capturedAt.formatted(date: .long, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Map(initialPosition: .region(.init(
                    center: sighting.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Marker(sighting.speciesCommonName, coordinate: sighting.coordinate)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if let notes = sighting.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(notes)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(sighting.speciesCommonName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
