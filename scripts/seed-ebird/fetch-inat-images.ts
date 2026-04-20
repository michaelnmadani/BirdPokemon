/**
 * Build a per-region training set from iNaturalist observations.
 *
 * For each species in `speciesCache` (filtered by region), download up to N
 * research-grade observation photos from iNaturalist's public API, saving
 * them into `data/training/<region>/<ebirdCode>/<obsId>.jpg` alongside a
 * `manifest.jsonl` entry with the photographer attribution and CC licence.
 *
 * Images are only used for local Create ML training and are never shipped
 * inside the app. Attribution is preserved so that if we later display
 * example imagery we can credit photographers.
 *
 * Usage:
 *   npm run fetch-images -- --region AU --perSpecies 300
 */
import "dotenv/config";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import fetch from "node-fetch";
import { mkdirSync, writeFileSync, appendFileSync, existsSync, readFileSync } from "fs";
import { join } from "path";
import pLimit from "p-limit";

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

const region = parseArg("region") ?? "AU";
const perSpecies = Number(parseArg("perSpecies") ?? "300");
const outDir = join("data", "training", region);

initializeApp({
  credential: cert(
    JSON.parse(
      readFileSync(
        process.env.GOOGLE_APPLICATION_CREDENTIALS ?? "./service-account.json",
        "utf-8"
      )
    )
  ),
  projectId: process.env.FIREBASE_PROJECT_ID,
});

const db = getFirestore();

type INatObservation = {
  id: number;
  photos: Array<{
    url: string;
    license_code?: string;
    attribution?: string;
  }>;
  taxon?: { name?: string };
};

type INatResponse = {
  total_results: number;
  results: INatObservation[];
};

async function observationsFor(scientificName: string, count: number) {
  const out: INatObservation[] = [];
  let page = 1;
  while (out.length < count) {
    const url = new URL("https://api.inaturalist.org/v1/observations");
    url.searchParams.set("taxon_name", scientificName);
    url.searchParams.set("quality_grade", "research");
    url.searchParams.set("photos", "true");
    url.searchParams.set("per_page", "200");
    url.searchParams.set("page", String(page));
    url.searchParams.set("license", "cc-by-nc,cc-by,cc0");
    const resp = await fetch(url, { headers: { "User-Agent": "BirdPokemon-Seed" } });
    if (!resp.ok) break;
    const data = (await resp.json()) as INatResponse;
    if (!data.results.length) break;
    out.push(...data.results);
    if (page * 200 >= data.total_results) break;
    page += 1;
  }
  return out.slice(0, count);
}

async function main() {
  mkdirSync(outDir, { recursive: true });
  const manifestPath = join(outDir, "manifest.jsonl");
  if (!existsSync(manifestPath)) writeFileSync(manifestPath, "");

  const snap = await db
    .collection("speciesCache")
    .where("regionCodes", "array-contains", region)
    .get();

  const limiter = pLimit(4);
  await Promise.all(
    snap.docs.map((doc) =>
      limiter(async () => {
        const data = doc.data();
        const code = data.ebirdCode as string;
        const sci = data.scientificName as string;
        const speciesDir = join(outDir, code);
        mkdirSync(speciesDir, { recursive: true });

        const observations = await observationsFor(sci, perSpecies);
        let saved = 0;
        for (const obs of observations) {
          for (const photo of obs.photos) {
            const url = photo.url.replace("/square.", "/large.");
            const path = join(speciesDir, `${obs.id}.jpg`);
            if (existsSync(path)) continue;
            try {
              const resp = await fetch(url);
              if (!resp.ok) continue;
              const buf = Buffer.from(await resp.arrayBuffer());
              writeFileSync(path, buf);
              appendFileSync(
                manifestPath,
                JSON.stringify({
                  speciesCode: code,
                  scientificName: sci,
                  obsId: obs.id,
                  url,
                  license: photo.license_code ?? null,
                  attribution: photo.attribution ?? null,
                  path,
                }) + "\n"
              );
              saved += 1;
              if (saved >= perSpecies) break;
            } catch {
              /* ignore one-off fetch errors */
            }
          }
          if (saved >= perSpecies) break;
        }
        console.log(`${code} (${sci}) → ${saved} images`);
      })
    )
  );

  console.log("Done. Images in", outDir);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
