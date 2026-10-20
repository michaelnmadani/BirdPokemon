/**
 * Build or refresh the bundled taxonomy for a region from eBird.
 *
 * Usage:
 *   npm run generate-bundle -- --region AU [--count 500] [--dry-run]
 *
 * Requires EBIRD_API_KEY in .env (free: https://ebird.org/api/keygen).
 *
 * How species are chosen: eBird's "recent observations" endpoint returns the
 * latest sighting of each species in a region, so one call per state says
 * little about how common a bird is. Instead we ask every county-level
 * region (AU has ~550 LGAs) and score each species by how many of them
 * reported it in the last 30 days — a decent proxy for "likely to be seen".
 *
 * Merging is non-destructive: species already in the bundle keep their
 * hand-curated colours, sizes and photos, and are never dropped. New species
 * get a size guessed from their taxonomic order and empty colours, to be
 * filled in by enrich.ts and by hand.
 */
import "dotenv/config";
import pLimit from "p-limit";
import {
  bundleExists, hasFlag, parseArg, readBundle, writeBundle,
  type BundledSpecies, type SizeCategory,
} from "./lib/bundle.ts";

type TaxonomyEntry = {
  sciName: string;
  comName: string;
  speciesCode: string;
  category: string;
  order: string;
  familySciName?: string;
  familyComName?: string;
};

type SubRegion = { code: string; name: string };

const EBIRD_BASE = "https://api.ebird.org/v2";
const apiKey = process.env.EBIRD_API_KEY;
if (!apiKey) {
  console.error("Set EBIRD_API_KEY in scripts/seed-ebird/.env");
  process.exit(1);
}

const region = (parseArg("region") ?? "AU").toUpperCase();
const existing = bundleExists(region) ? readBundle(region) : [];
const count = parseInt(parseArg("count") ?? String(Math.max(existing.length, 500)), 10);
const dryRun = hasFlag("dry-run");

async function ebirdGet<T>(path: string): Promise<T> {
  const url = `${EBIRD_BASE}${path}`;
  const res = await fetch(url, { headers: { "X-eBirdApiToken": apiKey! } });
  if (!res.ok) throw new Error(`eBird ${res.status} for ${url}: ${await res.text()}`);
  return (await res.json()) as T;
}

// Rough size bucket by taxonomic order, for brand-new species only.
const ORDER_TO_SIZE: Record<string, SizeCategory> = {
  Struthioniformes: "huge", Casuariiformes: "huge", Apterygiformes: "huge",
  Pelecaniformes: "large", Suliformes: "large", Phoenicopteriformes: "large",
  Accipitriformes: "large", Strigiformes: "medium", Ciconiiformes: "large",
  Gruiformes: "medium", Otidiformes: "large", Procellariiformes: "large",
  Sphenisciformes: "large", Galliformes: "medium", Anseriformes: "large",
  Podicipediformes: "medium", Columbiformes: "medium", Psittaciformes: "medium",
  Coraciiformes: "medium", Caprimulgiformes: "medium", Podargiformes: "medium",
  Falconiformes: "medium", Cuculiformes: "medium", Charadriiformes: "medium",
  Piciformes: "small", Passeriformes: "small",
};

async function frequencyScores(): Promise<Map<string, number>> {
  const subregions = await ebirdGet<SubRegion[]>(`/ref/region/list/subnational2/${region}`);
  const targets = subregions.length > 0 ? subregions : await ebirdGet<SubRegion[]>(`/ref/region/list/subnational1/${region}`);
  console.log(`Sampling recent observations across ${targets.length} sub-regions…`);

  const scores = new Map<string, number>();
  const limiter = pLimit(6);
  let done = 0;
  await Promise.all(
    targets.map((sub) =>
      limiter(async () => {
        try {
          const obs = await ebirdGet<{ speciesCode: string }[]>(`/data/obs/${sub.code}/recent?back=30&cat=species`);
          for (const code of new Set(obs.map((o) => o.speciesCode))) {
            scores.set(code, (scores.get(code) ?? 0) + 1);
          }
        } catch (err) {
          console.warn(`  ${sub.code}: ${err}`);
        }
        done += 1;
        if (done % 50 === 0) console.log(`  ${done}/${targets.length}`);
      })
    )
  );
  return scores;
}

function fromTaxonomy(t: TaxonomyEntry): BundledSpecies {
  return {
    ebirdCode: t.speciesCode,
    commonName: t.comName,
    scientificName: t.sciName,
    order: t.order,
    family: t.familySciName ?? "Unknown",
    familyCommonName: t.familyComName ?? null,
    category: t.category,
    sizeCategory: ORDER_TO_SIZE[t.order] ?? "medium",
    primaryColors: [],
    regionCodes: [region],
    thumbnailURL: null,
    thumbnailAttribution: null,
    thumbnailLicense: null,
    wikipediaURL: null,
    ebirdURL: `https://ebird.org/species/${t.speciesCode}`,
  };
}

async function main() {
  console.log(`Region ${region}: ${existing.length} species already bundled, target ${count}.`);
  const [taxonomy, regionalCodes] = await Promise.all([
    ebirdGet<TaxonomyEntry[]>("/ref/taxonomy/ebird?fmt=json&locale=en"),
    ebirdGet<string[]>(`/product/spplist/${region}`),
  ]);
  const regional = new Set(regionalCodes);
  const candidates = taxonomy.filter((t) => regional.has(t.speciesCode) && t.category === "species");
  console.log(`${candidates.length} species recorded in ${region}.`);

  const scores = await frequencyScores();
  const taxonOrder = new Map(taxonomy.map((t, i) => [t.speciesCode, i]));
  const byCode = new Map(existing.map((s) => [s.ebirdCode, s]));

  const ranked = [...candidates].sort((a, b) => (scores.get(b.speciesCode) ?? 0) - (scores.get(a.speciesCode) ?? 0));
  const chosen = new Map(byCode);
  for (const t of ranked) {
    if (chosen.size >= count) break;
    if (!chosen.has(t.speciesCode)) chosen.set(t.speciesCode, fromTaxonomy(t));
  }

  // Refresh names/taxonomy from eBird but keep curated fields.
  const taxonByCode = new Map(candidates.map((t) => [t.speciesCode, t]));
  const merged = [...chosen.values()].map((s) => {
    const t = taxonByCode.get(s.ebirdCode);
    if (!t) return s;
    return { ...s, commonName: t.comName, scientificName: t.sciName, order: t.order,
             family: t.familySciName ?? s.family, familyCommonName: t.familyComName ?? s.familyCommonName };
  });
  merged.sort((a, b) => (taxonOrder.get(a.ebirdCode) ?? 1e9) - (taxonOrder.get(b.ebirdCode) ?? 1e9));

  const added = merged.length - existing.length;
  console.log(`\n${merged.length} species (${added} new). New species need colours: run enrich.ts and fetch-thumbnails.ts.`);
  if (!dryRun) console.log(`Wrote ${writeBundle(region, merged)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
