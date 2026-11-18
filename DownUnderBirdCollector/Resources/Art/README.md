# Watercolour pictures

Filled by `scripts/artwork/watercolour.py` (see `scripts/artwork/README.md`):

- `art_<REGION>.json` — which photo each painting was made from, with its
  photographer and licence (the apps show these as credits)
- `<REGION>/<code>.jpg` — the paintings

Both apps use whatever is here and fall back to photos for the rest. This file
keeps the folder in git so the iOS project (which bundles it as a folder) builds
before any paintings exist.
