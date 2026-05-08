/**
 * Generate the bundled taxonomy JSON used by the iOS app for offline catalog
 * support. Run this whenever you want to refresh the on-device species list.
 *
 * Usage:
 *   npm run generate-bundle -- --region AU [--count 500]
 *
 * Requires EBIRD_API_KEY in your .env file (same key as seed.ts).
 *
 * The script:
 *   1. Fetches the full eBird taxonomy (global).
 *   2. Fetches the regional species code list for the requested region.
 *   3. Fetches recent observations across all subregions in parallel to build a
 *      frequency score for each species (proxy for "most commonly seen").
 *   4. Sorts species by frequency score, most-observed first.
 *   5. Takes the top --count species (default 500) and writes
 *      ../../BirdPokemon/Resources/Seeds/taxonomy_<REGION>.json
 *
 * Frequency scoring: for each observation record retrieved across all
 * subregions, the species' score is incremented by 1. Species appearing in
 * more checklists across the country score highest.
 *
 * Size categories are approximated from taxonomic order (raptors → large/huge,
 * passerines → small, etc.) so the bundled file is immediately useful without
 * running enrich.ts. Run enrich.ts afterwards for AVONET-derived precision.
 */

import "dotenv/config";
import { writeFileSync, mkdirSync } from "fs";
import { join, resolve } from "path";
import fetch from "node-fetch";

// ─── Types ────────────────────────────────────────────────────────────────────

type TaxonomyEntry = {
  sciName: string;
  comName: string;
  speciesCode: string;
  category: string;
  order: string;
  familyCode?: string;
  familySciName?: string;
  familyComName?: string;
};

type ObsEntry = {
  speciesCode: string;
  [key: string]: unknown;
};

type BundledSpecies = {
  ebirdCode: string;
  commonName: string;
  scientificName: string;
  order: string;
  family: string;
  familyCommonName: string | null;
  category: string;
  sizeCategory: string;
  primaryColors: string[];
  regionCodes: string[];
  thumbnailURL: null;
  wikipediaURL: null;
  ebirdURL: string;
};

// ─── Config ───────────────────────────────────────────────────────────────────

const EBIRD_BASE = "https://api.ebird.org/v2";

const apiKey = process.env.EBIRD_API_KEY;
if (!apiKey || apiKey === "replace_me_with_real_key") {
  console.error("Set EBIRD_API_KEY in scripts/seed-ebird/.env");
  process.exit(1);
}

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

const region = (parseArg("region") ?? "AU").toUpperCase();
const count = parseInt(parseArg("count") ?? "500", 10);

// AU subregions used for frequency sampling. Add more for non-AU regions.
const SUBREGIONS: Record<string, string[]> = {
  AU: ["AU-NSW", "AU-VIC", "AU-QLD", "AU-SA", "AU-WA", "AU-TAS", "AU-NT", "AU-ACT"],
  NZ: ["NZ-AUK", "NZ-WGN", "NZ-CAN", "NZ-OTA"],
  GB: ["GB-ENG", "GB-SCT", "GB-WLS"],
  US: ["US-CA", "US-TX", "US-FL", "US-NY", "US-WA", "US-CO", "US-AZ", "US-MN"],
};

// ─── eBird API helper ─────────────────────────────────────────────────────────

async function ebirdGet<T>(path: string): Promise<T> {
  const url = `${EBIRD_BASE}${path}`;
  const res = await fetch(url, { headers: { "X-eBirdApiToken": apiKey! } });
  if (!res.ok) {
    throw new Error(`eBird ${res.status} for ${url}: ${await res.text()}`);
  }
  return res.json() as Promise<T>;
}

// ─── Size approximation ───────────────────────────────────────────────────────

// Rough size bucket by taxonomic order — overridden later by AVONET enrichment.
const ORDER_TO_SIZE: Record<string, string> = {
  Struthioniformes: "huge",
  Rheiformes: "huge",
  Casuariiformes: "huge",
  Apterygiformes: "huge",
  Tinamiformes: "large",
  Pelecaniformes: "large",
  Suliformes: "large",
  Phoenicopteriformes: "large",
  Accipitriformes: "large",
  Strigiformes: "large",
  Ciconiiformes: "large",
  Gruiformes: "large",
  Otidiformes: "large",
  Gaviiformes: "large",
  Galliformes: "large",
  Anseriformes: "medium",
  Podicipediformes: "medium",
  Columbiformes: "medium",
  Psittaciformes: "medium",
  Coraciiformes: "medium",
  Bucerotiformes: "medium",
  Caprimulgiformes: "medium",
  Podargiformes: "medium",
  Falconiformes: "medium",
  Cuculiformes: "medium",
  Charadriiformes: "medium",
  Sphenisciformes: "medium",
  Piciformes: "small",
  Coliiformes: "small",
  Passeriformes: "small",
};

function sizeForOrder(order: string): string {
  return ORDER_TO_SIZE[order] ?? "medium";
}

// ─── Frequency scoring ────────────────────────────────────────────────────────

async function buildFrequencyMap(subregions: string[]): Promise<Map<string, number>> {
  const freq = new Map<string, number>();

  const results = await Promise.allSettled(
    subregions.map((sub) =>
      ebirdGet<ObsEntry[]>(
        `/data/obs/${sub}/recent?maxResults=10000&back=30&cat=species`
      )
    )
  );

  let fetched = 0;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (r.status === "rejected") {
      console.warn(`  Warning: failed to fetch obs for ${subregions[i]}: ${r.reason}`);
      continue;
    }
    const obs = r.value;
    fetched += obs.length;
    for (const o of obs) {
      freq.set(o.speciesCode, (freq.get(o.speciesCode) ?? 0) + 1);
    }
  }

  console.log(`  ${fetched} observation records across ${subregions.length} subregions.`);
  console.log(`  ${freq.size} unique species observed recently.`);
  return freq;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Region: ${region}  |  Target count: ${count}\n`);

  console.log("Fetching global eBird taxonomy and regional species list in parallel…");
  const [taxonomy, allCodes] = await Promise.all([
    ebirdGet<TaxonomyEntry[]>("/ref/taxonomy/ebird?fmt=json&locale=en"),
    ebirdGet<string[]>(`/product/spplist/${region}`),
  ]);
  console.log(`  Taxonomy: ${taxonomy.length} total entries.`);
  console.log(`  ${region} species list: ${allCodes.length} codes.`);

  const codeSet = new Set(allCodes);
  const regional = taxonomy.filter(
    (t) => codeSet.has(t.speciesCode) && t.category === "species"
  );
  console.log(`  ${regional.length} 'species'-category entries after intersection.\n`);

  const subregions = SUBREGIONS[region] ?? [region];
  console.log(`Fetching recent observations for frequency ranking (${subregions.join(", ")})…`);
  const freq = await buildFrequencyMap(subregions);

  console.log(`\nRanking by observation frequency and taking top ${count}…`);
  const sorted = [...regional].sort(
    (a, b) => (freq.get(b.speciesCode) ?? 0) - (freq.get(a.speciesCode) ?? 0)
  );
  const top = sorted.slice(0, count);

  // Report how many of the top N had real frequency data vs. taxonomic fallback.
  const withFreq = top.filter((t) => freq.has(t.speciesCode)).length;
  console.log(
    `  ${withFreq}/${top.length} have recent observation data; ` +
    `${top.length - withFreq} filled from taxonomic order.`
  );

  const bundled: BundledSpecies[] = top.map((t) => ({
    ebirdCode: t.speciesCode,
    commonName: t.comName,
    scientificName: t.sciName,
    order: t.order,
    family: t.familySciName ?? "Unknown",
    familyCommonName: t.familyComName ?? null,
    category: t.category,
    sizeCategory: sizeForOrder(t.order),
    primaryColors: [],
    regionCodes: [region],
    thumbnailURL: null,
    wikipediaURL: null,
    ebirdURL: `https://ebird.org/species/${t.speciesCode}`,
  }));

  const outDir = resolve(
    import.meta.dirname,
    "../../BirdPokemon/Resources/Seeds"
  );
  mkdirSync(outDir, { recursive: true });
  const outPath = join(outDir, `taxonomy_${region}.json`);
  writeFileSync(outPath, JSON.stringify(bundled, null, 2));

  console.log(`\nWrote ${bundled.length} species to:\n  ${outPath}`);
  console.log("Run enrich.ts afterwards to add AVONET-derived sizes and colour tags.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
