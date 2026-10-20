import SwiftUI

@main
struct DownUnderBirdCollectorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var catalog = SpeciesCatalog()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.sightings)
                .environmentObject(catalog)
                .environmentObject(location)
        }
    }
}
