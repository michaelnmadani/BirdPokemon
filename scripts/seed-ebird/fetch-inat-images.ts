/**
 * Build a per-region training set for the Core ML classifier from
 * iNaturalist research-grade observations.
 *
 * Saves `data/training/<REGION>/<ebirdCode>/<photoId>.jpg` plus a
 * `manifest.jsonl` line per image with the photographer credit and licence.
 * Images are only used for local Create ML training and never shipped.
 *
 * Usage:
 *   npm run fetch-images -- --region AU [--perSpecies 150] [--limit 10]
 *
 * Resumable: existing files are skipped, so you can stop and re-run.
 */
import { mkdirSync, writeFileSync, appendFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { parseArg, readBundle } from "./lib/bundle.ts";
import { DISPLAY_LICENCES, observations, photoSize, sleep } from "./lib/inat.ts";

const region = (parseArg("region") ?? "AU").toUpperCase();
const perSpecies = Number(parseArg("perSpecies") ?? "150");
const limit = parseArg("limit") ? Number(parseArg("limit")) : Infinity;
const outDir = join("data", "training", region);
const manifestPath = join(outDir, "manifest.jsonl");

async function fetchSpecies(code: string, scientificName: string) {
  const speciesDir = join(outDir, code);
  mkdirSync(speciesDir, { recursive: true });
  let saved = readdirSync(speciesDir).filter((f) => f.endsWith(".jpg")).length;

  for (let page = 1; saved < perSpecies && page <= 10; page++) {
    const data = await observations({
      taxon_name: scientificName,
      quality_grade: "research",
      photos: "true",
      photo_license: DISPLAY_LICENCES.join(","),
      per_page: "100",
      page: String(page),
    });
    if (data.results.length === 0) break;

    for (const obs of data.results) {
      // One photo per observation keeps the set varied.
      const photo = obs.photos.find((p) => DISPLAY_LICENCES.includes(p.license_code?.toLowerCase() ?? ""));
      if (!photo) continue;
      const path = join(speciesDir, `${photo.id}.jpg`);
      if (existsSync(path)) continue;
      try {
        const url = photoSize(photo.url, "medium");
        const resp = await fetch(url);
        if (!resp.ok) continue;
        writeFileSync(path, Buffer.from(await resp.arrayBuffer()));
        appendFileSync(manifestPath, JSON.stringify({
          speciesCode: code, scientificName, obsId: obs.id, photoId: photo.id, url,
          license: photo.license_code ?? null, attribution: photo.attribution ?? null, path,
        }) + "\n");
        saved++;
        if (saved >= perSpecies) break;
      } catch {
        /* skip one-off download errors */
      }
    }
    await sleep(1000);
  }
  return saved;
}

async function main() {
  mkdirSync(outDir, { recursive: true });
  if (!existsSync(manifestPath)) writeFileSync(manifestPath, "");

  const species = readBundle(region).slice(0, limit);
  for (const [i, s] of species.entries()) {
    const n = await fetchSpecies(s.ebirdCode, s.scientificName);
    console.log(`[${i + 1}/${species.length}] ${s.ebirdCode} (${s.commonName}) → ${n} images`);
  }
  console.log(`Done. Images in ${outDir}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
