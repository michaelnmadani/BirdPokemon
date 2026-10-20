# Training the bird identification model

The app identifies birds with an on-device Core ML image classifier,
`BirdClassifier_<REGION>.mlmodel`, whose labels are eBird species codes. No
model is bundled yet — until there is one, the app asks people to choose the
species themselves, which works fine.

Training needs a Mac with Xcode (Create ML ships with it).

## 1. Download training photos (any machine with Node 20+)

```sh
cd scripts/seed-ebird
npm install
npm run fetch-images -- --region AU --perSpecies 150
```

This saves CC-licensed, research-grade iNaturalist photos to
`scripts/seed-ebird/data/training/AU/<ebirdCode>/` with a `manifest.jsonl` of
photographer credits. 500 species × 150 photos is about 75,000 images
(~6 GB) and takes several hours because the script respects iNaturalist's
rate limit. It is resumable — stop and re-run any time. Use `--limit 20` for
a quick trial run on the first 20 species.

## 2. Train (Mac)

```sh
swift scripts/train-model/train.swift AU
```

Species with fewer than 40 photos are skipped. The script prints training and
validation accuracy and writes
`DownUnderBirdCollector/Resources/ML/BirdClassifier_AU.mlmodel`.

Prefer a GUI? Open Create ML (`open -a "Create ML"`), make an Image
Classification project, point Training Data at the same folder and export the
model to the same path.

## 3. Ship it

```sh
xcodegen generate
```

Build and run: the capture flow now shows "We think this is a…" with a
confidence bar, and falls back to the manual species picker when the model
isn't sure (top guess under 85% or close to the runner-up).

## Notes

- Training photos are **not** committed: they're large and many are
  CC BY-NC. Each contributor regenerates them locally (`data/` is gitignored).
- A 500-class model trained with Create ML's scene-print feature extractor is
  small (a few MB), which keeps the app download light.
