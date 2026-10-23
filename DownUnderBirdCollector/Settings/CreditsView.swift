import SwiftUI

/// Every photo, watercolour and recording in the field guide with its creator
/// and licence, as the Creative Commons licences require.
struct CreditsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @State private var search = ""

    private var species: [Species] { catalog.species(in: appState.selectedRegion) }

    private var shown: [Species] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return species }
        return species.filter { s in
            [s.commonName, s.thumbnailAttribution, s.callAttribution].compactMap { $0 }.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        List {
            Section {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(shown) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.commonName).font(.subheadline.weight(.semibold))
                        if s.thumbnail != nil {
                            creditLine("Photo", s.thumbnailAttribution ?? "iNaturalist observer", licence: s.thumbnailLicense)
                        } else {
                            creditLine("Photo", "none yet", licence: nil)
                        }
                        if let art = catalog.artwork(for: s)?.art {
                            creditLine("Watercolour", "adapted from the photo above", licence: art.license)
                        }
                        if s.call != nil {
                            creditLine("Call", "\(s.callAttribution ?? "Recording") via \(s.callSource == "xeno-canto" ? "xeno-canto" : "iNaturalist")",
                                       licence: s.callLicense)
                        }
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
            Section("Also") {
                Text("Species names and taxonomy: eBird / Clements Checklist (Cornell Lab of Ornithology). Sound identification: BirdNET (K. Lisa Yang Center for Conservation Bioacoustics, Cornell Lab of Ornithology & Chemnitz University of Technology), CC BY-NC-SA 4.0. Size estimates from AVONET (CC BY 4.0).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search, prompt: "Search credits")
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: String {
        let photos = species.filter { $0.thumbnail != nil }.count
        let calls = species.filter { $0.call != nil }.count
        let paintings = species.filter { catalog.artwork(for: $0) != nil }.count
        return "\(photos) species photos by iNaturalist contributors, \(calls) recordings from iNaturalist and xeno-canto"
            + (paintings > 0 ? ", and \(paintings) watercolours painted from those photos" : "")
            + ". Each is used under the Creative Commons licence shown. Watercolours are adaptations of the credited photo and share its licence."
    }

    @ViewBuilder
    private func creditLine(_ kind: String, _ text: String, licence: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(kind):").bold()
            Text(text)
            if let licence, let url = Self.licenceURL(licence) {
                Text("·")
                Link(Species.licenceLabel(licence), destination: url)
            } else if let licence {
                Text("· \(Species.licenceLabel(licence))")
            }
        }
        .foregroundStyle(.secondary)
    }

    static func licenceURL(_ code: String) -> URL? {
        let paths = [
            "cc0": "publicdomain/zero/1.0/", "cc-by": "licenses/by/4.0/", "cc-by-sa": "licenses/by-sa/4.0/",
            "cc-by-nc": "licenses/by-nc/4.0/", "cc-by-nc-sa": "licenses/by-nc-sa/4.0/",
            "cc-by-nd": "licenses/by-nd/4.0/", "cc-by-nc-nd": "licenses/by-nc-nd/4.0/",
        ]
        return paths[code.lowercased()].flatMap { URL(string: "https://creativecommons.org/\($0)") }
    }
}
