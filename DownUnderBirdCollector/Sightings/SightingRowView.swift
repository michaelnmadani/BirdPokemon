import SwiftUI

struct SightingRowView: View {
    let sighting: Sighting

    @EnvironmentObject private var store: SightingStore
    @EnvironmentObject private var catalog: SpeciesCatalog

    var body: some View {
        HStack(spacing: 12) {
            // Sightings logged without a photo show the field guide picture.
            AsyncRemoteImage(url: store.thumbnailURL(for: sighting) ?? catalog.picture(for: catalog.species(code: sighting.speciesCode)))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(sighting.speciesCommonName)
                    .font(.body.weight(.medium))
                Text(sighting.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    if let coordinate = sighting.coordinate {
                        Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                    } else {
                        Text("No location")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
