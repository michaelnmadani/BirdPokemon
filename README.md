# BirdPokemon

A bird-watching app for iPhone that turns spotting birds into a Pokemon-style collection game. Photograph a bird, get it auto-identified on-device, and save the sighting to your personal collection with its GPS location.

## Status

Scaffolded MVP. Regional rollout order: Australia (AU) -> New Zealand (NZ) -> United Kingdom (GB) -> United States (US).

Phase 7 (NZ) code support landed: `MLClassifier` now downloads non-bundled
region models from Firebase Storage via `ModelRepository` and caches them in
`Application Support/Models/`. The data pipeline (seed + train + upload) still
has to be run manually for each new region — see the rollout section below.

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

## Regional rollout (Phase 7+)

Adding a new region (starting with New Zealand) does **not** require an App
Store resubmission — the app discovers new species via Firestore and pulls the
classifier model from Firebase Storage on first use.

Run these steps on a Mac with a service account in `scripts/seed-ebird/service-account.json`:

```sh
cd scripts/seed-ebird

# 1. Seed speciesCache for the new region
npm run seed -- --region NZ

# 2. Enrich with AVONET size buckets + hand-tagged colors
npm run enrich -- --region NZ

# 3. Build the training set from iNaturalist (may take hours)
npm run fetch-images -- --region NZ --perSpecies 300
```

Then train and upload the model (see `scripts/train-model/README.md`):

```sh
# Create ML: Image Classifier, train on scripts/seed-ebird/data/training/NZ/
# Export as BirdClassifier_NZ.mlmodel, then:

firebase storage:upload BirdClassifier_NZ.mlmodel \
  --destination models/BirdClassifier_NZ.mlmodel
```

First time a user selects NZ in the region picker, the app will download and
compile the model (shown via `ClassificationViewModel.preparingModel`). Repeat
the same flow for `GB` (Phase 8) and `US` (Phase 9).

## Privacy & licensing

This app is for **non-commercial use**. Data sources:

- eBird API 2.0 (non-commercial free tier)
- iNaturalist (CC-BY-NC images for ML training)
- AVONET (CC-BY-4.0 morphological data for size buckets)
- GBIF (CC0 / CC-BY occurrence data)
- Wikipedia / Wikidata (CC-BY-SA descriptions and thumbnails)

GPS coordinates are user-private by default; sightings are only visible to the user who recorded them.
