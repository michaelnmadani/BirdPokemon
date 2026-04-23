# BirdPokemon

A bird-watching app for iPhone that turns spotting birds into a Pokemon-style collection game. Photograph a bird, get it auto-identified on-device, and save the sighting to your personal collection with its GPS location.

## Status

Scaffolded MVP. Regional rollout order: Australia (AU) -> New Zealand (NZ) -> United Kingdom (GB) -> United States (US).

- **Code:** Phases 0–6 plus multi-region model download (Phase 7 prereq) — `MLClassifier` loads the AU model from the bundle and downloads NZ/GB/US models from Firebase Storage via `ModelRepository`, caching them in `Application Support/Models/`.
- **Data (AU):** not yet seeded in Firestore. Run the pipeline in **Regional data pipeline** below.
- **ML (AU):** `BirdClassifier_AU.mlmodel` not yet trained or bundled — the app's auto-ID will return `modelUnavailable` until a model is dropped in `BirdPokemon/Resources/ML/`.

See the implementation plan at `/root/.claude/plans/i-want-a-bird-lovely-crane.md` for architecture and phased build order.

## Requirements

- macOS with Xcode 15.3 or later
- iOS 17.0+ target device (or simulator, with Photo Library fallback for camera)
- Apple Developer account (for Sign in with Apple + device deployment)
- Firebase project (Auth + Firestore + Storage)
- eBird API key (free for non-commercial use: https://ebird.org/api/keygen)
- Homebrew packages: `xcodegen`, `firebase-cli`, `node` (for seed scripts)

## First-time setup

1. **Install tools**
   ```sh
   brew install xcodegen firebase-cli node
   ```

2. **Create the Xcode project**
   ```sh
   xcodegen generate
   open BirdPokemon.xcodeproj
   ```

3. **Add your secrets**
   ```sh
   cp Secrets.example.xcconfig Secrets.xcconfig
   # edit Secrets.xcconfig and paste your EBIRD_API_KEY
   ```

4. **Add Firebase config**
   - Create a Firebase project at https://console.firebase.google.com
   - Add an iOS app with bundle id matching `project.yml` (`com.example.birdpokemon`)
   - Download `GoogleService-Info.plist` and place it at `BirdPokemon/Supporting/GoogleService-Info.plist`
   - Enable Auth (Apple, Email/Password), Firestore, and Storage in the console

5. **Deploy security rules**
   ```sh
   firebase login
   firebase use --add  # pick your project
   firebase deploy --only firestore:rules,storage:rules,firestore:indexes
   ```

6. **Seed the species catalog (Australia first)**
   ```sh
   cd scripts/seed-ebird
   npm install
   cp .env.example .env   # add EBIRD_API_KEY and path to firebase service-account.json
   npm run seed -- --region AU
   ```

7. **Build & run**
   - Open `BirdPokemon.xcodeproj`
   - Select an iPhone simulator or physical device
   - Cmd+R

## Project layout

See the plan file for the full file tree. Key directories:

- `BirdPokemon/App` — app entry, delegate, root routing
- `BirdPokemon/Auth` — Sign in with Apple + email/password flows
- `BirdPokemon/Capture` — camera, ML classification, sighting confirmation
- `BirdPokemon/Services` — Firebase, eBird, Core Location, ML wrappers
- `BirdPokemon/Models` — Codable data models
- `BirdPokemon/Resources/ML` — bundled `BirdClassifier_AU.mlmodel` (drop in after training)
- `BirdPokemon/Resources/Seeds` — bundled per-region species seeds
- `scripts/seed-ebird` — Node admin scripts to populate Firestore `speciesCache`
- `scripts/train-model` — Create ML training inputs (data not tracked in git)

## Regional data pipeline

The same sequence ships each region. Australia (AU) is the first
implementation; NZ / GB / US follow without an App Store resubmission because
the app discovers new species via Firestore and pulls the classifier model
from Firebase Storage on first use.

Prerequisites (one-time per project):
- **Enable Firestore** on the Firebase project:
  `https://console.firebase.google.com/project/<projectId>/firestore` → *Create database*
- Drop a Firebase admin service-account JSON at
  `scripts/seed-ebird/service-account.json` (gitignored).
- Create `scripts/seed-ebird/.env` with `EBIRD_API_KEY`, `FIREBASE_PROJECT_ID`,
  and `GOOGLE_APPLICATION_CREDENTIALS=./service-account.json`.
- Download AVONET: https://figshare.com/s/b990722d72a26b5bfead →
  `scripts/seed-ebird/data/AVONET.csv`.

Run on a Mac with unrestricted network (eBird and iNaturalist block some
sandboxes). Substitute `AU` with `NZ` / `GB` / `US` for later regions.

```sh
cd scripts/seed-ebird
npm install

# 0. Verify auth + Firestore reachability
npm run probe

# 1. Seed speciesCache from eBird taxonomy (~900 docs for AU)
npm run seed -- --region AU

# 2. Generate a starter colors_AU.json from the shipped dictionary
npm run generate-colors -- --region AU

# 3. Enrich with AVONET size buckets + colors from step 2
npm run enrich -- --region AU --avonet ./data/AVONET.csv --colors ./data/colors_AU.json

# 4. Export the full region list into the app bundle for offline first-launch
npm run export-seed -- --region AU

# 5. Build the ML training set from iNaturalist (hours, tens of GB)
npm run fetch-images -- --region AU --perSpecies 300
```

Then train and ship the Core ML model (see `scripts/train-model/README.md`):

```sh
# Create ML: Image Classifier, train on scripts/seed-ebird/data/training/AU/
# Export as BirdClassifier_AU.mlmodel, then:

# AU ships bundled — drop it into the app bundle:
cp BirdClassifier_AU.mlmodel BirdPokemon/Resources/ML/

# Subsequent regions upload to Firebase Storage instead (downloaded on demand):
firebase storage:upload BirdClassifier_NZ.mlmodel \
  --destination models/BirdClassifier_NZ.mlmodel
```

First time a user selects a non-bundled region in the picker, the app
downloads and compiles the model (shown via
`ClassificationViewModel.preparingModel`).

## Privacy & licensing

This app is for **non-commercial use**. Data sources:

- eBird API 2.0 (non-commercial free tier)
- iNaturalist (CC-BY-NC images for ML training)
- AVONET (CC-BY-4.0 morphological data for size buckets)
- GBIF (CC0 / CC-BY occurrence data)
- Wikipedia / Wikidata (CC-BY-SA descriptions and thumbnails)

GPS coordinates are user-private by default; sightings are only visible to the user who recorded them.
