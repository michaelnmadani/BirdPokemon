/**
 * Generate the bundled taxonomy JSON used by the iOS app for offline catalog
 * support. Run this whenever you want to refresh the on-device species list.
 *
 * Usage:
 *   npm run generate-bundle -- --region AU
 *
 * Requires EBIRD_API_KEY in your .env file (same key as seed.ts).
 *
 * The script:
 *   1. Fetches the full eBird taxonomy (global).
 *   2. Fetches the regional species code list for the requested region.
 *   3. Intersects to produce the regional species set.
 *   4. Writes ../../BirdPokemon/Resources/Seeds/taxonomy_<REGION>.json
 *
 * Size categories are approximated from taxonomic order (raptors → large/huge,
 * songbirds → small/medium, etc.) so the bundled file is immediately useful
 * without running enrich.ts. Run enrich.ts afterwards against Firestore to
 * get precise AVONET-derived sizes.
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
  // huge (> 60 cm)
  Struthioniformes: "huge",
  Rheiformes: "huge",
  Casuariiformes: "huge",
  Apterygiformes: "huge",
  Tinamiformes: "large",
  Pelecaniformes: "large",
  Suliformes: "large",
  Phoenicopteriformes: "large",

  // large (35–60 cm)
  Accipitriformes: "large",
  Strigiformes: "large",
  Ciconiiformes: "large",
  Anseriformes: "medium",  // ducks vary a lot
  Gruiformes: "large",
  Otidiformes: "large",
  Podicipediformes: "medium",

  // medium (20–35 cm)
  Columbiformes: "medium",
  Psittaciformes: "medium",  // wide range — left as medium default
  Coraciiformes: "medium",
  Bucerotiformes: "medium",
  Piciformes: "small",
  Caprimulgiformes: "medium",
  Podargiformes: "medium",
  Falconiformes: "medium",
  Coliiformes: "small",
  Cuculiformes: "medium",
  Galliformes: "large",
  Charadriiformes: "medium",
  Gaviiformes: "large",
  Sphenisciformes: "medium",

  // small (10–20 cm)
  Passeriformes: "small",

  // default
  _default: "medium",
};

function sizeForOrder(order: string): string {
  return ORDER_TO_SIZE[order] ?? ORDER_TO_SIZE["_default"];
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Fetching global eBird taxonomy…`);
  const taxonomy = await ebirdGet<TaxonomyEntry[]>(
    "/ref/taxonomy/ebird?fmt=json&locale=en"
  );
  console.log(`  ${taxonomy.length} total entries.`);

  console.log(`Fetching species list for ${region}…`);
  const codes = await ebirdGet<string[]>(`/product/spplist/${region}`);
  console.log(`  ${codes.length} species codes for ${region}.`);

  const codeSet = new Set(codes);
  const regional = taxonomy.filter(
    (t) => codeSet.has(t.speciesCode) && t.category === "species"
  );
  console.log(`  ${regional.length} 'species'-category entries after intersection.`);

  const bundled: BundledSpecies[] = regional.map((t) => ({
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
  console.log(`\nWrote ${bundled.length} species to ${outPath}`);
  console.log(
    "Run enrich.ts afterwards to add AVONET-derived sizes and colour tags."
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
