/**
 * Seed `speciesCache` in Firestore for one region at a time.
 *
 * Usage:
 *   npm run seed -- --region AU
 *
 * What it does:
 *   1. Pulls the eBird taxonomy (full global list).
 *   2. Pulls the species list for the requested region.
 *   3. Intersects them and writes one doc per species to Firestore.
 *
 * Size + colour enrichment lives in enrich.ts and should be run afterwards.
 */
import "dotenv/config";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import fetch from "node-fetch";
import { readFileSync } from "fs";

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

const EBIRD_BASE = "https://api.ebird.org/v2";
const apiKey = process.env.EBIRD_API_KEY;
if (!apiKey) {
  console.error("Missing EBIRD_API_KEY in .env");
  process.exit(1);
}

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .map((arg, index, all) => [arg.replace(/^--/, ""), all[index + 1]])
    .filter(([k]) => k.startsWith("region"))
);
const region = args.region ?? "AU";
console.log(`Seeding region: ${region}`);

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

async function ebirdGet<T>(path: string): Promise<T> {
  const response = await fetch(`${EBIRD_BASE}${path}`, {
    headers: { "X-eBirdApiToken": apiKey! },
  });
  if (!response.ok) {
    throw new Error(`eBird ${response.status}: ${await response.text()}`);
  }
  return (await response.json()) as T;
}

async function main() {
  console.log("Fetching global taxonomy…");
  const taxonomy = await ebirdGet<TaxonomyEntry[]>("/ref/taxonomy/ebird?fmt=json&locale=en");
  console.log(`Taxonomy has ${taxonomy.length} entries.`);

  console.log(`Fetching species list for ${region}…`);
  const regionCodes = await ebirdGet<string[]>(`/product/spplist/${region}`);
  console.log(`Region has ${regionCodes.length} species.`);

  const set = new Set(regionCodes);
  const regional = taxonomy.filter(
    (t) => set.has(t.speciesCode) && t.category === "species"
  );
  console.log(`Writing ${regional.length} species to speciesCache…`);

  const writer = db.bulkWriter();
  for (const entry of regional) {
    const ref = db.collection("speciesCache").doc(entry.speciesCode);
    writer.set(
      ref,
      {
        ebirdCode: entry.speciesCode,
        commonName: entry.comName,
        scientificName: entry.sciName,
        order: entry.order,
        family: entry.familySciName ?? "Unknown",
        familyCommonName: entry.familyComName ?? null,
        category: entry.category,
        sizeCategory: "medium", // enrich.ts overwrites with AVONET-derived value
        primaryColors: [], // enrich.ts fills from hand-tagged JSON
        regionCodes: FieldValue.arrayUnion(region),
        thumbnailURL: null,
        wikipediaURL: null,
        ebirdURL: `https://ebird.org/species/${entry.speciesCode}`,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  await writer.close();
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
