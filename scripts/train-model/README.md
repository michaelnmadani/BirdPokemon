# Training a regional BirdClassifier

The iOS app expects one Core ML model per supported region, named
`BirdClassifier_<REGION>.mlmodel` and either bundled or downloaded into the
`Resources/ML` folder.

## Prerequisites

- macOS with Xcode 15+ (for Create ML)
- A folder of training images built by `scripts/seed-ebird/fetch-inat-images.ts`
  (see that script for format). One subfolder per species, named by eBird code.
- At least 50 images per class. Classes with fewer than 50 images should be
  moved out of the training folder — Create ML can still produce a model, but
  the sparse classes will dominate bad predictions.

## Steps

1. Open Create ML: `open -a "Create ML"`.
2. New document → Image Classification.
3. Training Data → point at `scripts/seed-ebird/data/training/AU/` (or whichever region).
4. Augmentations: enable horizontal flip, rotation ±15°, crop.
5. Algorithm: Transfer Learning on "MobileNetV2" (best size/accuracy trade-off).
6. Train.
7. Evaluate with a held-out validation set and note top-1 / top-5 accuracy.
8. Export → `BirdClassifier_AU.mlmodel`.
9. Drop into `BirdPokemon/Resources/ML/` for AU (bundled with the app) or
   upload to Firebase Storage at `models/BirdClassifier_<REGION>.mlmodel` for
   NZ / GB / US (downloaded on first region selection).

## Notes

- Training data is **not** checked in — it's large (tens of GB) and many
  photos are CC-BY-NC which is incompatible with code hosting ToS that assume
  redistributable content. Each contributor regenerates locally.
- Preserve `manifest.jsonl` from the fetch step alongside the model so we
  can credit photographers if we ever display sample imagery.
