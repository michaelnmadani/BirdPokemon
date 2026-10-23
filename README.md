# Down Under Bird Collector

An iPhone app that turns birdwatching into a collection game. Photograph a
bird, identify it, and it joins your collection with the date and place you
saw it. Fill the album one species at a time — 500 Australian birds to find.

- **Collection** — every species as a card; the ones you haven't found yet
  show in greyscale until you photograph them. Field guide pictures can be the
  photo or a watercolour painted from it (see
  [`scripts/artwork/`](scripts/artwork/README.md)). Choose small, medium or large
  pictures, and group the album by bird group, family, size or colour.
- **Field Guide** — search and filter all 500 species by size, colour and
  family, or browse by group (flightless birds, parrots & cockatoos, birds of
  prey, …) and by genus (rosellas, kookaburras, fairywrens, …). Photos are
  credited to their iNaturalist photographers. **Hear its call** plays a
  recording of each bird (from xeno-canto or iNaturalist, credited).
- **Capture** — camera with telephoto zoom, a photo from your library, or
  no photo at all for birds you only saw or heard. Choose or confirm the
  species and save. Location comes from GPS or from the photo itself.
- **Identify by sound** — listen through the microphone, or analyse a
  recording, and BirdNET names the birds calling. It runs on the device, so
  audio never leaves it. Tap a bird to log the sighting.
- **Nearby** — every bird spotted within 5 km of where you are: your own
  sightings, plus recent eBird reports from other birdwatchers if you add a
  free eBird API key in Settings. Filter to the ones you haven't collected.
- **Sightings & Map** — your log, with every sighting pinned on a map.

Everything works offline and stays on the phone. No account needed.

There's also a **web version** in [`web/`](web/) for trying the app on any
phone or computer before the iOS build is on your device.

## Quick start

### iOS app (needs a Mac with Xcode 16.3 or later)

```sh
brew install xcodegen
scripts/birdnet/fetch-model.sh        # BirdNET sound-ID model (52 MB, not in git)
scripts/birdnet/fetch-tflite-ios.sh   # TensorFlow Lite runtime it runs on
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
| `scripts/artwork/` | Paints a watercolour of every species photo with a local AI Image Studio |
| `scripts/birdnet/` | Fetch the BirdNET sound-ID model (`models/birdnet/`) and the iOS TensorFlow Lite runtime (`Vendor/`) — neither is in git |
| `project.yml`, `Config/` | XcodeGen project definition and build settings |
| `.github/workflows/` | CI for iOS and web, TestFlight upload, photo fetching |

## How it fits together

- **Bird groups**: curated groups live in `Seeds/groups.json` (matched by
  order, family or species code); genus groups are generated from any genus
  with two or more species, named from their members' common names.
- **Species data**: `taxonomy_AU.json` ships inside the app. It's loaded at
  launch and decoded leniently, so one odd record can never empty the catalog.
- **Sightings**: saved on the device (Application Support: a JSON index and
  two JPEGs per sighting, included in iPhone backups). "Collected" is worked
  out from your sightings, so deleting your only sighting of a species
  un-collects it.
- **Identification**: the app uses `BirdClassifier_AU.mlmodel` if one is
  bundled; until then you choose the species from the field guide. Training
  a model: [`scripts/train-model/README.md`](scripts/train-model/README.md).
- **Bird calls**: `scripts/seed-ebird/fetch-calls.ts` (or the *Fetch bird
  calls* workflow) picks one recording per species — xeno-canto first (set a
  free `XENO_CANTO_API_KEY` secret), else iNaturalist — and stores the link
  and credit in `taxonomy_AU.json`. Calls stream when played; they're not
  bundled.
- **Sound ID**: BirdNET V2.4 (6,522 classes, 3-second windows at 48 kHz).
  `scripts/birdnet/fetch-model.sh` downloads it (from the pinned `birdnetlib`
  PyPI wheel, checked by SHA-256); CI does this automatically. BirdNET labels
  are matched to field-guide species by scientific, then common, name — 365
  of the 500 Australian species. The web app runs it with LiteRT.js (WASM)
  and downloads the 52 MB model on first use; iOS runs it with TensorFlow
  Lite and bundles it.
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
estimates. Map tiles © OpenStreetMap contributors (web version). Bird calls
from xeno-canto and iNaturalist recordists under their Creative Commons
licences, credited with each recording. Sound identification by
[BirdNET](https://birdnet.cornell.edu) (K. Lisa Yang Center for Conservation
Bioacoustics, Cornell Lab of Ornithology & Chemnitz University of Technology);
the model is licensed **CC BY-NC-SA 4.0**, so the app must stay
non-commercial (free, no ads or in-app purchases) while it includes it.
Runtime: LiteRT.js / TensorFlow Lite (Apache 2.0).
