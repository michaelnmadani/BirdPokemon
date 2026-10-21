# Down Under Bird Collector — web version

A test version of the app that runs in any modern browser and works fully
offline after the first visit. It has the same screens as the iOS app
(Collection, Field Guide with bird groups, Capture, Nearby, Sightings with a
map, Settings) and reads the
same species data.

Differences from iOS: the species is always chosen by hand (no on-device
model), and sightings are stored in the browser (IndexedDB) rather than in
the app.

## Run it

```sh
cd web
npm install      # dev-only: Leaflet + LiteRT.js (copied into the build) and Playwright
npm start        # builds to web/dist and serves http://localhost:5173
```

Sound ID needs the BirdNET model, which isn't in git. Fetch it once with
`../scripts/birdnet/fetch-model.sh` (needs Python 3 and pip); without it the
build still works and the *Identify by sound* screen says it isn't included.
The model (52 MB) is not precached: the app downloads it the first time you
use sound ID and keeps it for offline use.

No framework and no runtime dependencies: `web/dist` is plain static files
you can host anywhere.

## Testing on a phone

The camera, GPS and offline mode need HTTPS (or `localhost`), so a LAN
address like `http://192.168.1.5:5173` only half-works on a phone. Options:

- **GitHub Pages** — the `Web` workflow deploys `web/dist` whenever the
  default branch changes. Enable it once under the repo's *Settings → Pages
  → Source: GitHub Actions*. Then open
  `https://<user>.github.io/<repo>/` on your iPhone.
- **Any static host** (Netlify, Vercel, Cloudflare Pages): upload `web/dist`.

On iPhone, open the page in Safari and choose **Share → Add to Home Screen**.
It then launches full-screen like an app and works without signal. In
*Settings → Download species photos* you can cache all species photos before
going bush.

## Tests

```sh
npm test         # unit tests: species model, filters, groups, nearby, sound ID helpers
npm run e2e      # builds, then drives headless Chromium through browsing,
                 # two captures (photo GPS + live GPS), offline reload, delete,
                 # Nearby, and BirdNET on its example recording (if fetched with
                 # ../scripts/birdnet/fetch-model.sh --example)
SCREENSHOTS=1 npm run e2e   # also saves screenshots to web/test-results/
```

## Layout

| Path | |
| --- | --- |
| `src/index.html`, `src/css/app.css` | Shell and styles (light + dark) |
| `src/js/app.js` | Router, tab bar, start-up |
| `src/js/model.js` | Species model and filters (mirrors the Swift models) |
| `src/js/store.js` | Sightings + photos in IndexedDB |
| `src/js/exif.js`, `src/js/images.js` | Photo date/GPS and resizing |
| `src/js/views/` | One file per screen |
| `src/js/soundid.js`, `soundid-core.js`, `mic-worklet.js` | BirdNET sound ID: model loading, microphone, scoring |
| `src/sw.js` | Service worker: precaches the app, caches species photos and (on first use) the sound model |
| `scripts/build.mjs` | Copies species data + Leaflet, stamps the service worker |
