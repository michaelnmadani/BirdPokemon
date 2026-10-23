// Builds web/dist: copies the app, the bundled species data (shared with the
// iOS app) and Leaflet, then stamps the service worker with a content hash and
// the list of files to precache. No dependencies beyond Node itself.
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'src');
const dist = join(root, 'dist');
const seeds = resolve(root, '../DownUnderBirdCollector/Resources/Seeds');
const leaflet = join(root, 'node_modules/leaflet/dist');
const litert = join(root, 'node_modules/@litertjs');
const birdnet = resolve(root, '../models/birdnet');

if (!existsSync(leaflet)) {
  console.error('Leaflet not found — run `npm install` in web/ first.');
  process.exit(1);
}

rmSync(dist, { recursive: true, force: true });
cpSync(src, dist, { recursive: true });

// Species data: every taxonomy_<REGION>.json the iOS app ships.
mkdirSync(join(dist, 'data'), { recursive: true });
const regions = [];
for (const file of readdirSync(seeds).sort()) {
  const match = file.match(/^taxonomy_([A-Z]{2})\.json$/);
  if (!match) continue;
  cpSync(join(seeds, file), join(dist, 'data', file));
  regions.push(match[1]);
}
writeFileSync(join(dist, 'data/regions.json'), JSON.stringify(regions));
cpSync(join(seeds, 'groups.json'), join(dist, 'data/groups.json'));

// Leaflet (BSD-2-Clause) for the map screen.
mkdirSync(join(dist, 'vendor/leaflet'), { recursive: true });
for (const file of ['leaflet.js', 'leaflet.css']) cpSync(join(leaflet, file), join(dist, 'vendor/leaflet', file));
cpSync(join(leaflet, 'images'), join(dist, 'vendor/leaflet/images'), { recursive: true });
cpSync(resolve(root, 'node_modules/leaflet/LICENSE'), join(dist, 'vendor/leaflet/LICENSE'));

// LiteRT.js (Apache-2.0) runs BirdNET in the browser. Only the two WASM
// builds it picks between without cross-origin isolation are shipped.
mkdirSync(join(dist, 'vendor/litert'), { recursive: true });
cpSync(join(litert, 'core/dist/index.js'), join(dist, 'vendor/litert/litert.js'));
cpSync(join(litert, 'wasm-utils/dist/index.js'), join(dist, 'vendor/litert/wasm-utils.js'));
for (const variant of ['litert_wasm_internal', 'litert_wasm_compat_internal']) {
  for (const ext of ['js', 'wasm']) cpSync(join(litert, `core/wasm/${variant}.${ext}`), join(dist, `vendor/litert/${variant}.${ext}`));
}

// BirdNET model (CC BY-NC-SA 4.0), fetched by scripts/birdnet/fetch-model.sh.
const birdnetFiles = ['BirdNET_GLOBAL_6K_V2.4_Model_FP32.tflite', 'BirdNET_GLOBAL_6K_V2.4_Labels.txt', 'LICENSE-BirdNET.txt'];
const hasBirdnet = birdnetFiles.every((f) => existsSync(join(birdnet, f)));
if (hasBirdnet) {
  mkdirSync(join(dist, 'models/birdnet'), { recursive: true });
  for (const f of birdnetFiles) cpSync(join(birdnet, f), join(dist, 'models/birdnet', f));
} else {
  console.warn('BirdNET model not found — building without sound ID (run scripts/birdnet/fetch-model.sh).');
}

// Watercolours painted by scripts/artwork/watercolour.py (none until it has been run).
const artRoot = resolve(root, '../DownUnderBirdCollector/Resources/Art');
let paintings = 0;
for (const region of existsSync(artRoot) ? readdirSync(artRoot) : []) {
  const manifest = join(artRoot, `art_${region}.json`);
  if (!statSync(join(artRoot, region)).isDirectory() || !existsSync(manifest)) continue;
  cpSync(manifest, join(dist, 'data', `art_${region}.json`));
  cpSync(join(artRoot, region), join(dist, 'art', region), { recursive: true });
  paintings += Object.keys(JSON.parse(readFileSync(manifest, 'utf8')).species ?? {}).length;
}

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

// Big sound-ID files and the watercolours are cached on first use (or via
// Settings → Download species photos) instead of at install.
const onDemand = (f) => /[\\/](models|vendor[\\/]litert|art)[\\/]/.test(relative(dist, f).replace(/^/, '/'));
const files = walk(dist).filter((f) => !f.endsWith('sw.js') && !f.endsWith('LICENSE') && !onDemand(f)).sort();
const swPath = join(dist, 'sw.js');
const hash = createHash('sha256').update(readFileSync(swPath));
for (const f of files) hash.update(relative(dist, f)).update(readFileSync(f));
const version = hash.digest('hex').slice(0, 12);

const precache = ['./', ...files.map((f) => `./${relative(dist, f).split('\\').join('/')}`)];
writeFileSync(swPath, readFileSync(swPath, 'utf8')
  .replace('__VERSION__', version)
  .replace('__PRECACHE__', JSON.stringify(precache, null, 2)));

const indexPath = join(dist, 'index.html');
writeFileSync(indexPath, readFileSync(indexPath, 'utf8').replace('__BUILD__', version));

const size = files.reduce((n, f) => n + statSync(f).size, 0);
console.log(`Built web/dist (${regions.join(', ')} data, ${precache.length} precached files, ${(size / 1e6).toFixed(2)} MB, sound ID ${hasBirdnet ? 'included' : 'not included'}, version ${version}).`);
