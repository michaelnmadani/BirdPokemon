/**
 * Fetch one representative CC-licensed thumbnail URL per species from
 * iNaturalist and write it into the bundled taxonomy JSON.
 *
 * Photos are NOT uploaded to Firebase Storage here — the iNaturalist CDN URL
 * is stored directly. Run a separate mirror-to-storage step once you have a
 * Firebase service account configured.
 *
 * Usage:
 *   npm run fetch-thumbnails -- --region AU [--limit 1]
 *
 * --limit N   only process the first N species (omit for all)
 * --dry-run   print what would change without writing
 */

import "dotenv/config";
import { readFileSync, writeFileSync } from "fs";
import { join, resolve } from "path";
import fetch from "node-fetch";

// ─── Types ────────────────────────────────────────────────────────────────────

type BundledSpecies = {
  ebirdCode: string;
  commonName: string;
  scientificName: string;
  thumbnailURL: string | null;
  [key: string]: unknown;
};

type INatPhoto = {
  url: string;
  license_code?: string | null;
  attribution?: string | null;
};

type INatResult = {
  id: number;
  photos: INatPhoto[];
};

type INatResponse = {
  total_results: number;
  results: INatResult[];
};

// ─── Args ─────────────────────────────────────────────────────────────────────

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

const region = (parseArg("region") ?? "AU").toUpperCase();
const limit = parseArg("limit") ? parseInt(parseArg("limit")!, 10) : null;
const dryRun = process.argv.includes("--dry-run");

// ─── iNaturalist helper ───────────────────────────────────────────────────────

const INAT_BASE = "https://api.inaturalist.org/v1";

// Accepted licences — CC0 and CC-BY variants are safe for app use.
const ALLOWED_LICENCES = new Set(["cc0", "cc-by", "cc-by-nc", "cc-by-sa", "cc-by-nc-sa"]);

async function fetchThumbnail(scientificName: string): Promise<string | null> {
  const url = new URL(`${INAT_BASE}/observations`);
  url.searchParams.set("taxon_name", scientificName);
  url.searchParams.set("quality_grade", "research");
  url.searchParams.set("photos", "true");
  url.searchParams.set("per_page", "10");
  url.searchParams.set("page", "1");
  url.searchParams.set("order_by", "votes"); // most popular first → best photos

  let resp;
  try {
    resp = await fetch(url.toString(), {
      headers: { "User-Agent": "BirdPokemon-Seed/1.0 (contact via github)" },
    });
  } catch (err) {
    console.warn(`  Network error for ${scientificName}: ${err}`);
    return null;
  }

  if (!resp.ok) {
    console.warn(`  iNat ${resp.status} for ${scientificName}`);
    return null;
  }

  const data = (await resp.json()) as INatResponse;
  if (!data.results?.length) return null;

  for (const obs of data.results) {
    for (const photo of obs.photos) {
      const licence = photo.license_code?.toLowerCase() ?? null;
      if (!licence || !ALLOWED_LICENCES.has(licence)) continue;

      // iNat URLs come in /square/ (75px) — upgrade to /medium/ (~500px)
      const mediumUrl = photo.url
        .replace("/square.", "/medium.")
        .replace("/small.", "/medium.");

      return mediumUrl;
    }
  }

  return null;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const jsonPath = resolve(
    import.meta.dirname,
    "../../BirdPokemon/Resources/Seeds",
    `taxonomy_${region}.json`
  );

  const species: BundledSpecies[] = JSON.parse(readFileSync(jsonPath, "utf-8"));
  const toProcess = limit !== null ? species.slice(0, limit) : species;

  console.log(`Fetching thumbnails for ${toProcess.length} species (region: ${region})…`);
  if (dryRun) console.log("DRY RUN — no files will be written.\n");

  let updated = 0;
  let skipped = 0;
  let failed = 0;

  for (let i = 0; i < toProcess.length; i++) {
    const sp = toProcess[i];

    if (sp.thumbnailURL) {
      console.log(`[${i + 1}/${toProcess.length}] SKIP (already set) ${sp.commonName}`);
      skipped++;
      continue;
    }

    process.stdout.write(`[${i + 1}/${toProcess.length}] ${sp.commonName} (${sp.scientificName}) … `);
    const photoUrl = await fetchThumbnail(sp.scientificName);

    if (photoUrl) {
      sp.thumbnailURL = photoUrl;
      updated++;
      console.log(`✓ ${photoUrl}`);
    } else {
      failed++;
      console.log("✗ no CC photo found");
    }

    // Be polite to iNaturalist — 2 requests/sec max
    await new Promise((r) => setTimeout(r, 500));
  }

  console.log(`\nResults: ${updated} updated, ${skipped} skipped, ${failed} not found.`);

  if (!dryRun && updated > 0) {
    writeFileSync(jsonPath, JSON.stringify(species, null, 2));
    console.log(`Wrote updated taxonomy to:\n  ${jsonPath}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
