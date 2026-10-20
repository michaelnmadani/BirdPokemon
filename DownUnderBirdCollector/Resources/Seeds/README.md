# Bundled species data

`taxonomy_<REGION>.json` is the single source of truth for species. The iOS
app bundles it, the web app copies it at build time, and
`scripts/seed-ebird/seed.ts` can mirror it into Firestore.

`taxonomy_AU.json` holds 500 Australian species with hand-tagged colours,
size categories and, for most, an iNaturalist photo.

Each record:

| Field | Notes |
| --- | --- |
| `ebirdCode` | eBird species code, e.g. `laukoo1`; also the ML model label |
| `commonName`, `scientificName` | eBird English and scientific names |
| `order`, `family`, `familyCommonName` | eBird taxonomy |
| `sizeCategory` | `tiny` `small` `medium` `large` `huge` |
| `primaryColors` | from `red orange yellow green blue brown black white gray pink purple` |
| `regionCodes` | e.g. `["AU"]` |
| `thumbnailURL`, `thumbnailAttribution`, `thumbnailLicense` | iNaturalist photo, credit and CC licence |
| `wikipediaURL`, `ebirdURL` | links |

## Editing

Edit by hand or with the scripts in `scripts/seed-ebird` (see its README),
then validate:

```sh
cd scripts/seed-ebird
npm run validate -- --region AU          # CI runs this too
npm run validate -- --region AU --fix    # folds e.g. "rufous" → orange
```
