import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.authStatus {
            case .unknown:
                LoadingView(message: "Loading…")
            case .signedOut:
                AuthView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.default, value: appState.authStatus)
    }
}

struct MainTabView: View {
    @State private var selection: Tab = .capture

    enum Tab: Hashable {
        case collection, catalog, capture, nearby, sightings
    }

    var body: some View {
        TabView(selection: $selection) {
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
                .tag(Tab.collection)

            CatalogView()
                .tabItem { Label("Field Guide", systemImage: "book") }
                .tag(Tab.catalog)

            CaptureFlowView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
                .tag(Tab.capture)

            NearbyView()
                .tabItem { Label("Nearby", systemImage: "mappin.and.ellipse") }
                .tag(Tab.nearby)

            SightingsListView()
                .tabItem { Label("Sightings", systemImage: "list.bullet") }
                .tag(Tab.sightings)
        }
    }
}
