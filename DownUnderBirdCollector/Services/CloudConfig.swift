import Foundation
import FirebaseCore

/// Cloud sync is opt-in. Drop a `GoogleService-Info.plist` into
/// `DownUnderBirdCollector/Supporting/` and regenerate the project: the app
/// then asks people to sign in and syncs sightings through Firebase. Without
/// that file everything stays on the device and no account is needed.
enum CloudConfig {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var hasFirebaseConfig: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// Configures Firebase once if a config file is bundled. Returns whether
    /// cloud mode is active.
    @discardableResult
    static func configureIfAvailable() -> Bool {
        guard hasFirebaseConfig, !isRunningTests else { return false }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}
