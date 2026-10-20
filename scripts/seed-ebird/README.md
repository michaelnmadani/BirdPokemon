# Species data scripts

Node 20+ scripts that maintain the bundled species list
(`DownUnderBirdCollector/Resources/Seeds/taxonomy_<REGION>.json`). None of
them need Firebase except `seed.ts`.

```sh
cd scripts/seed-ebird
npm install
cp .env.example .env    # only needed for generate-bundle / seed
```

| Command | What it does |
| --- | --- |
| `npm run validate -- --region AU [--fix]` | Checks the file decodes in both apps; `--fix` normalises colours/sizes |
| `npm run fetch-thumbnails -- --region AU [--refresh-attribution]` | Adds a CC-licensed iNaturalist photo + photographer credit per species |
| `npm run generate-bundle -- --region AU [--count 600]` | Adds commonly-seen species from eBird (needs `EBIRD_API_KEY`); never drops or overwrites curated data |
| `npm run enrich -- --region AU --avonet AVONET_eBird.csv [--write]` | Suggests sizes from AVONET morphology |
| `npm run fetch-images -- --region AU` | Downloads training photos for the ML model (see `scripts/train-model`) |
| `npm run seed -- --region AU` | Optional: mirrors the file into Firestore `speciesCache` |
| `npm test` / `npm run typecheck` | Script unit tests and type checks (run in CI) |

The **Fetch species photos** GitHub Action runs `fetch-thumbnails` in the
cloud and commits the result, so you don't need to run it locally.
