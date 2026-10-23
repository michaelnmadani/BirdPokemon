import SwiftUI
import MapKit
import CoreLocation

/// Birds spotted within 5 km of where you are: your own sightings (works
/// offline) plus recent eBird reports from other birdwatchers (with a key).
struct NearbyView: View {
    private enum Show: String, CaseIterable, Identifiable {
        case all = "Everything"
        case missing = "Not collected yet"
        var id: String { rawValue }
    }

    private enum EBirdState {
        case idle
        case noKey
        case loading
        case loaded(fetchedAt: Date, cached: Bool)
        case failed(String)
    }

    @EnvironmentObject private var store: SightingStore
    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var location: LocationService
    @AppStorage(EBirdClient.apiKeyDefaultsKey) private var apiKey = ""

    @State private var center: CLLocationCoordinate2D?
    @State private var locationError: String?
    @State private var reports: [EBirdObservation] = []
    @State private var ebird: EBirdState = .idle
    @State private var show: Show = .all
    @State private var camera: MapCameraPosition = .automatic

    private var entries: [NearbyEntry] {
        guard let center else { return [] }
        return NearbySummary.entries(center: center, mine: store.sightings, reports: reports) { catalog.species(code: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    map
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Birds spotted within \(Int(NearbySummary.radiusKm)) km of where you are.")
                }

                if let center {
                    content(center: center)
                } else if let locationError {
                    Section {
                        Text(locationError).foregroundStyle(.secondary)
                        Button("Try again") { Task { await refresh() } }
                    }
                } else {
                    Section { HStack { ProgressView(); Text("Finding your location…") } }
                }
            }
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .onChange(of: apiKey) { _, _ in Task { await loadReports() } }
        }
    }

    private struct Pin: Identifiable {
        enum Kind { case here, mine, report }
        let id: String
        let title: String
        let coordinate: CLLocationCoordinate2D
        let kind: Kind
    }

    /// Everything on the map as flat lists (no `if` inside the map builder).
    private var pins: (here: [Pin], others: [Pin]) {
        guard let center else { return ([], []) }
        var others: [Pin] = []
        for entry in entries {
            for sighting in entry.mine {
                if let coordinate = sighting.coordinate {
                    others.append(Pin(id: "mine-\(sighting.id)", title: sighting.speciesCommonName, coordinate: coordinate, kind: .mine))
                }
            }
            if let report = entry.report, let lat = report.lat, let lng = report.lng {
                others.append(Pin(id: "report-\(entry.code)", title: entry.name,
                                  coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), kind: .report))
            }
        }
        return ([Pin(id: "here", title: "You", coordinate: center, kind: .here)], others)
    }

    private var map: some View {
        let pins = self.pins
        return Map(position: $camera) {
            ForEach(pins.here) { pin in
                MapCircle(center: pin.coordinate, radius: NearbySummary.radiusKm * 1000)
                    .foregroundStyle(Color.accentColor.opacity(0.08))
                    .stroke(Color.accentColor, lineWidth: 2)
                Annotation(pin.title, coordinate: pin.coordinate) {
                    Circle().fill(.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            ForEach(pins.others) { pin in
                Marker(pin.title, systemImage: pin.kind == .mine ? "bird.fill" : "binoculars.fill", coordinate: pin.coordinate)
                    .tint(pin.kind == .mine ? Color.accentColor : .orange)
            }
        }
        .mapControls { MapScaleView() }
    }

    @ViewBuilder
    private func content(center: CLLocationCoordinate2D) -> some View {
        let all = entries
        let missing = all.filter { !store.capturedCodes.contains($0.code) }
        let shown = show == .all ? all : missing

        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(all.count) species spotted within \(Int(NearbySummary.radiusKm)) km").font(.headline)
                Text("\(missing.count) you haven't collected yet").font(.subheadline).foregroundStyle(.secondary)
            }
            ebirdNotice
            Picker("Show", selection: $show) {
                ForEach(Show.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        Section {
            if shown.isEmpty {
                Text(show == .missing && !all.isEmpty
                     ? "You've collected everything spotted here. Nice!"
                     : "Nothing recorded within \(Int(NearbySummary.radiusKm)) km yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { entry in
                if let species = entry.species {
                    NavigationLink { SpeciesDetailView(species: species) } label: { row(entry) }
                } else {
                    row(entry)
                }
            }
        }
    }

    @ViewBuilder
    private var ebirdNotice: some View {
        switch ebird {
        case .noKey:
            Text("Add a free eBird API key in Settings (gear on the Collection tab) to also see what other birdwatchers reported here in the last 30 days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .loading:
            HStack { ProgressView(); Text("Checking eBird…").font(.footnote) }
        case .loaded(let fetchedAt, let cached):
            Text(cached
                 ? "Includes eBird reports saved \(fetchedAt.formatted(date: .abbreviated, time: .shortened)) (offline)."
                 : "Includes eBird reports from the last 30 days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    private func row(_ entry: NearbyEntry) -> some View {
        HStack(spacing: 12) {
            AsyncRemoteImage(url: catalog.picture(for: entry.species))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if store.capturedCodes.contains(entry.code) {
                        CapturedBadgeView().offset(x: 6, y: -6)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.body.weight(.medium))
                Text(entry.scientificName).font(.footnote).italic().foregroundStyle(.secondary)
                if !entry.mine.isEmpty {
                    Text("You: \(entry.mine.count) sighting\(entry.mine.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let report = entry.report {
                    Text("eBird: \(NearbySummary.daysAgo(report.observedAt))\(report.locName.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if entry.species == nil {
                    Text("Not in the field guide yet").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Loading

    private func refresh() async {
        do {
            let fix = try await location.currentLocation(maxAge: 120)
            center = fix.coordinate
            locationError = nil
            camera = .region(MKCoordinateRegion(center: fix.coordinate,
                                                latitudinalMeters: NearbySummary.radiusKm * 2400,
                                                longitudinalMeters: NearbySummary.radiusKm * 2400))
            await loadReports()
        } catch {
            locationError = error.localizedDescription
        }
    }

    private func loadReports() async {
        guard let center else { return }
        guard EBirdClient.apiKey() != nil else {
            reports = []
            ebird = .noKey
            return
        }
        ebird = .loading
        do {
            let result = try await EBirdClient.recentNearby(latitude: center.latitude, longitude: center.longitude,
                                                            km: NearbySummary.radiusKm)
            reports = result.reports
            ebird = .loaded(fetchedAt: result.fetchedAt, cached: result.cached)
        } catch {
            reports = []
            ebird = .failed(error.localizedDescription)
        }
    }
}
