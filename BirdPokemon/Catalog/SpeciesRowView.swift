import SwiftUI

struct SpeciesRowView: View {
    let species: Species
    let isCaptured: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncRemoteImage(url: species.thumbnailURL.flatMap(URL.init(string:)))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if isCaptured {
                        CapturedBadgeView()
                            .offset(x: 6, y: -6)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(species.commonName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(species.scientificName)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(species.familyCommonName ?? species.family)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(species.sizeCategory.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(species.primaryColors.prefix(3)) { color in
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
