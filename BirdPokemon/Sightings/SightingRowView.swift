import SwiftUI

struct SightingRowView: View {
    let sighting: Sighting

    var body: some View {
        HStack(spacing: 12) {
            AsyncRemoteImage(url: URL(string: sighting.thumbnailURL ?? sighting.photoURL))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(sighting.speciesCommonName)
                    .font(.body.weight(.medium))
                Text(sighting.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let name = sighting.locationName, !name.isEmpty {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(format: "%.4f, %.4f", sighting.latitude, sighting.longitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
