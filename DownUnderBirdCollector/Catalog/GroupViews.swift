import SwiftUI

/// Horizontal row of the curated bird groups, shown above the field guide.
struct GroupChipsRow: View {
    let groups: [SpeciesGroup]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups.filter { $0.kind == .group }) { group in
                    NavigationLink {
                        GroupDetailView(group: group)
                    } label: {
                        HStack(spacing: 4) {
                            Text(group.emoji)
                            Text(group.name).fontWeight(.semibold)
                            Text("\(group.species.count)").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    GroupsListView()
                } label: {
                    Text("All groups & genera ›")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal)
        }
    }
}

/// A group as a list row: cover photo, name and collection progress.
struct GroupRowView: View {
    let group: SpeciesGroup

    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore

    var body: some View {
        let have = group.species.filter(store.isCaptured).count
        HStack(spacing: 12) {
            AsyncRemoteImage(url: group.species.lazy.compactMap { catalog.picture(for: $0) }.first)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title).font(.body.weight(.medium))
                if let genus = group.genus {
                    Text("Genus \(genus)").font(.footnote).italic().foregroundStyle(.secondary)
                }
                Text("\(have) of \(group.species.count) collected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Every bird group and genus in the selected region, searchable.
struct GroupsListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @State private var searchText = ""

    private func filtered(_ kind: SpeciesGroup.Kind) -> [SpeciesGroup] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.groups(in: appState.selectedRegion).filter { group in
            guard group.kind == kind else { return false }
            guard !needle.isEmpty else { return true }
            let text = group.searchText + " " + group.species.map(\.commonName).joined(separator: " ").lowercased()
            return text.contains(needle)
        }
    }

    var body: some View {
        List {
            let groups = filtered(.group)
            let genera = filtered(.genus)
            if !groups.isEmpty {
                Section("Bird groups") {
                    ForEach(groups) { group in
                        NavigationLink { GroupDetailView(group: group) } label: { GroupRowView(group: group) }
                    }
                }
            }
            if !genera.isEmpty {
                Section {
                    ForEach(genera) { group in
                        NavigationLink { GroupDetailView(group: group) } label: { GroupRowView(group: group) }
                    }
                } header: {
                    Text("Genera")
                } footer: {
                    Text("Closely related species that share a genus.")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search groups, e.g. parrots or rosellas")
        .navigationTitle("Groups")
        .overlay {
            if filtered(.group).isEmpty && filtered(.genus).isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "No groups match")
            }
        }
    }
}

/// The species in one group, with collection progress.
struct GroupDetailView: View {
    let group: SpeciesGroup

    @EnvironmentObject private var store: SightingStore

    var body: some View {
        let have = group.species.filter(store.isCaptured).count
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let genus = group.genus {
                        Text("Genus \(genus)").italic().foregroundStyle(.secondary)
                    }
                    Text("\(have) of \(group.species.count) collected").font(.headline)
                    ProgressView(value: Double(have), total: Double(max(group.species.count, 1)))
                }
                .padding(.vertical, 4)
            }
            Section("Species") {
                ForEach(group.species) { species in
                    NavigationLink {
                        SpeciesDetailView(species: species)
                    } label: {
                        SpeciesRowView(species: species, isCaptured: store.isCaptured(species))
                    }
                }
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
