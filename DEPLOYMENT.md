# Getting Down Under Bird Collector onto iPhones

There are two ways to build and ship the app. **Path A** uses Xcode on a Mac
and is the most direct. **Path B** uses the GitHub Actions workflow in this
repo, so you can ship to TestFlight without owning a Mac.

Both need:

- An **Apple Developer Program** membership (US$99 / A$149 a year) —
  <https://developer.apple.com/programs/>
- A **bundle ID** you own, e.g. `com.yourname.downunderbirdcollector`.
  The placeholder `com.downunderbirdcollector.app` in `Config/App.xcconfig`
  is only for local builds.

---

## Path A — Xcode on a Mac

1. Install Xcode 16.3+ from the App Store, then `brew install xcodegen`.
2. Configure signing:
   ```sh
   cp Secrets.example.xcconfig Secrets.xcconfig
   ```
   Set `DEVELOPMENT_TEAM` (Xcode → Settings → Accounts, or
   developer.apple.com → Membership) and `APP_BUNDLE_ID`.
3. `xcodegen generate && open DownUnderBirdCollector.xcodeproj`
4. **Run on your iPhone**: plug it in, choose it as the run destination, ⌘R.
   The first time, enable *Settings → Privacy & Security → Developer Mode*
   on the phone and trust the developer certificate when asked.
5. **TestFlight**: in App Store Connect create the app (*Apps → + → New
   App*, pick your bundle ID). In Xcode choose *Any iOS Device*, then
   *Product → Archive → Distribute App → App Store Connect → Upload*.
   The build appears in TestFlight after processing (10–30 minutes).

## Path B — GitHub Actions (no Mac needed)

The **TestFlight** workflow (`.github/workflows/testflight.yml`) archives,
signs and uploads the app using an App Store Connect API key.

### One-time setup

1. **Register the bundle ID**: developer.apple.com → Certificates,
   Identifiers & Profiles → Identifiers → **+** → App IDs → App. Enter your
   bundle ID and tick **Sign In with Apple**.
2. **Create the app record**: App Store Connect → Apps → **+** → New App.
   Name *Down Under Bird Collector*, choose that bundle ID, SKU anything.
3. **Create an API key**: App Store Connect → Users and Access →
   Integrations → App Store Connect API → Team Keys → **+**. Give it
   **Admin** access (needed for cloud-managed signing certificates).
   Download the `.p8` file (you only get one chance) and note the
   **Key ID** and **Issuer ID**.
4. **Add to GitHub** (repo → Settings → Secrets and variables → Actions):

   | Kind | Name | Value |
   | --- | --- | --- |
   | Secret | `ASC_KEY_ID` | Key ID from step 3 |
   | Secret | `ASC_ISSUER_ID` | Issuer ID from step 3 |
   | Secret | `ASC_KEY_P8` | Entire contents of the `.p8` file, including the BEGIN/END lines |
   | Secret | `APPLE_TEAM_ID` | Your 10-character team ID |
   | Variable | `APP_BUNDLE_ID` | Your bundle ID |

### Each release

Actions tab → **TestFlight** → *Run workflow* (optionally set the version,
e.g. `1.0.1`). The build number is the workflow run number, so it always
increases. Install the **TestFlight** app on your iPhone and accept the
invite for your Apple ID (App Store Connect → TestFlight → Internal Testing).

> The workflow follows Apple's documented `xcodebuild` cloud-signing flow but
> hasn't been run against a real account yet. If the first run fails, the
> log artifact shows the signing error. The usual causes are an API key
> without Admin access, or a bundle ID that doesn't match the app record.

---

## Before submitting to the App Store

- **Privacy policy URL** (required). [`PRIVACY.md`](PRIVACY.md) is a ready
  starting point; publish it (e.g. with GitHub Pages) and paste the URL into
  App Store Connect.
- **App Privacy** answers: with the default on-device storage the app
  collects **no data** ("Data Not Collected"). If you turn on Firebase sync,
  declare Photos, Precise Location, Email Address and User ID (linked to the
  user, not used for tracking), and add them to
  `DownUnderBirdCollector/Supporting/PrivacyInfo.xcprivacy`.
- **Screenshots**: 6.9" iPhone screenshots (1320 × 2868) are required. Run
  the app in the iPhone 17 Pro Max simulator and press ⌘S.
- **Category**: Education (already set in Info.plist). Age rating: 4+.
- **Encryption**: already declared as none (`ITSAppUsesNonExemptEncryption`).
- **Licensing**: eBird data and many iNaturalist photos (CC BY-NC) are
  licensed for **non-commercial** use, so keep the app free with no ads or
  in-app purchases unless you replace those sources.
- **Home-screen name**: iOS shows about 12 characters under the icon, so
  "Down Under Bird Collector" appears as "Down Under B…". The App Store name
  can stay in full; to show something shorter on the home screen, change
  `CFBundleDisplayName` in `project.yml` (e.g. to "Bird Collector").
- **Sign in with Apple** is only used in cloud mode. If you never plan to
  enable cloud sync, you can remove the `entitlements` block from
  `project.yml`.

## Optional: cloud sync with Firebase

1. Create a Firebase project, add an iOS app with your bundle ID, and enable
   Authentication (Apple + Email/Password), Firestore and Storage.
2. Download `GoogleService-Info.plist` into
   `DownUnderBirdCollector/Supporting/` (it's gitignored) and run
   `xcodegen generate`.
3. Deploy the rules: `firebase deploy --only firestore:rules,storage`.

The app detects the file at launch: people then sign in, and their sightings
sync across devices. Settings includes the account deletion Apple requires.
For CI builds with cloud sync, add the plist as a base64 secret and write it
out in the workflow before `xcodegen generate`.
