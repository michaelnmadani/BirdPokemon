import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var message: String?
    @AppStorage(EBirdClient.apiKeyDefaultsKey) private var ebirdKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Region") {
                    if catalog.availableRegions.count > 1 {
                        Picker("Region", selection: $appState.selectedRegion) {
                            ForEach(catalog.availableRegions) { region in
                                Text("\(region.flag) \(region.displayName)").tag(region)
                            }
                        }
                    } else {
                        LabeledContent("Region", value: "\(appState.selectedRegion.flag) \(appState.selectedRegion.displayName)")
                        Text("New Zealand, the UK and the US are planned for later versions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Sightings", value: "\(store.sightings.count)")
                    LabeledContent("Species collected", value: "\(store.capturedCodes.count)")
                    switch appState.mode {
                    case .local:
                        LabeledContent("Stored", value: "On this iPhone")
                    case .cloud:
                        LabeledContent("Account", value: appState.accountEmail ?? "Signed in")
                        Button("Sign out") { appState.signOut() }
                    }
                    Button(appState.mode == .cloud ? "Delete account and all data" : "Delete all sightings", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(isDeleting)
                } header: {
                    Text("Your data")
                } footer: {
                    Text(appState.mode == .local
                         ? "Sightings and photos are saved only on this device and included in your iPhone backups."
                         : "Sightings sync to your account so they're available on any device you sign in on.")
                }

                Section {
                    SecureField("eBird API key", text: $ebirdKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a free key at ebird.org", destination: URL(string: "https://ebird.org/api/keygen")!)
                } header: {
                    Text("Nearby birds (eBird)")
                } footer: {
                    Text("Lets the Nearby tab include what other birdwatchers reported within 5 km in the last 30 days. Stored only on this iPhone.")
                }

                if let message {
                    Section { Text(message).font(.footnote) }
                }

                Section("About") {
                    LabeledContent("Version", value: Self.versionString)
                    Text("Species data from eBird (Cornell Lab of Ornithology). Species photos by iNaturalist contributors, credited on each species page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !catalog.loadIssues.isEmpty {
                        ForEach(catalog.loadIssues, id: \.self) { issue in
                            Text(issue).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isDeleting { LoadingView(message: "Deleting…") }
            }
            .confirmationDialog(
                appState.mode == .cloud ? "Delete your account?" : "Delete all sightings?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await deleteEverything() }
                }
            } message: {
                Text("This removes every sighting and photo and can't be undone.")
            }
        }
    }

    private func deleteEverything() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await appState.deleteAllData()
            message = "All sightings deleted."
        } catch {
            message = "Couldn't finish deleting: \(error.localizedDescription) If you're signed in, sign out and back in, then try again."
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
