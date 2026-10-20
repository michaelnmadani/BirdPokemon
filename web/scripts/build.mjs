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

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

const files = walk(dist).filter((f) => !f.endsWith('sw.js') && !f.endsWith('LICENSE')).sort();
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
console.log(`Built web/dist (${regions.join(', ')} data, ${precache.length} files, ${(size / 1e6).toFixed(2)} MB, version ${version}).`);
