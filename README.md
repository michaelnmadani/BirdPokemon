# Down Under Bird Collector

An iPhone app that turns birdwatching into a collection game. Photograph a
bird, identify it, and it joins your collection with the date and place you
saw it. Fill the album one species at a time — 500 Australian birds to find.

- **Collection** — every species as a card; the ones you haven't found stay
  hidden until you photograph them.
- **Field Guide** — search and filter all 500 species by size, colour and
  family, with photos credited to their iNaturalist photographers.
- **Capture** — camera with telephoto zoom (or pick from your photo
  library), choose or confirm the species, and save. Location comes from
  GPS or from the photo itself.
- **Sightings & Map** — your log, with every sighting pinned on a map.

Everything works offline and stays on the phone. No account needed.

There's also a **web version** in [`web/`](web/) for trying the app on any
phone or computer before the iOS build is on your device.

## Quick start

### iOS app (needs a Mac with Xcode 16.3 or later)

```sh
brew install xcodegen
xcodegen generate
open DownUnderBirdCollector.xcodeproj
```

Pick an iPhone simulator and press ⌘R. To run on your own iPhone, copy
`Secrets.example.xcconfig` to `Secrets.xcconfig`, put in your Apple team ID,
regenerate, and select your phone. Shipping to TestFlight / the App Store is
covered step by step in **[DEPLOYMENT.md](DEPLOYMENT.md)**.

### Web version (any computer with Node 20+)

```sh
cd web
npm install
npm start          # → http://localhost:5173
```

Open it, browse, and "capture" birds with any photo. After the first load it
works with no connection at all. See [`web/README.md`](web/README.md) for
testing on a phone.

## Project layout

| Path | What's there |
| --- | --- |
| `DownUnderBirdCollector/` | SwiftUI app (iOS 17+) |
| `DownUnderBirdCollector/Resources/Seeds/` | Bundled species data — the single source of truth for both apps |
| `DownUnderBirdCollectorTests/` | Unit tests (catalog decoding, storage, image processing, filters) |
| `web/` | Offline web app (no framework, no runtime dependencies) |
| `scripts/seed-ebird/` | Node scripts that maintain the species data |
| `scripts/train-model/` | Create ML script to train the bird-identification model |
| `project.yml`, `Config/` | XcodeGen project definition and build settings |
| `.github/workflows/` | CI for iOS and web, TestFlight upload, photo fetching |

## How it fits together

- **Species data**: `taxonomy_AU.json` ships inside the app. It's loaded at
  launch and decoded leniently, so one odd record can never empty the catalog.
- **Sightings**: saved on the device (Application Support: a JSON index and
  two JPEGs per sighting, included in iPhone backups). "Collected" is worked
  out from your sightings, so deleting your only sighting of a species
  un-collects it.
- **Identification**: the app uses `BirdClassifier_AU.mlmodel` if one is
  bundled; until then you choose the species from the field guide. Training
  a model: [`scripts/train-model/README.md`](scripts/train-model/README.md).
- **Optional cloud sync**: drop a Firebase `GoogleService-Info.plist` into
  `DownUnderBirdCollector/Supporting/` and the app switches to sign-in
  (Apple or email) with sightings synced through Firestore and Storage.
  Rules are in `firestore.rules` / `storage.rules`.

## Tests

| What | Command | Runs in CI |
| --- | --- | --- |
| iOS unit tests | ⌘U in Xcode | `iOS` workflow (also an unsigned Release device build) |
| Species data | `cd scripts/seed-ebird && npm run validate && npm test` | `iOS` workflow |
| Web unit + end-to-end | `cd web && npm test && npm run e2e` | `Web` workflow |

## Data and licences

Non-commercial use. Species names and taxonomy from eBird (Cornell Lab of
Ornithology). Species photos from iNaturalist contributors under Creative
Commons licences, credited in the app. AVONET morphology (CC BY 4.0) for size
estimates. Map tiles © OpenStreetMap contributors (web version).
