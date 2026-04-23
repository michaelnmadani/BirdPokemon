/**
 * Export a region's speciesCache from Firestore into the app bundle seed,
 * replacing the placeholder `BirdPokemon/Resources/Seeds/taxonomy_<REGION>.json`.
 *
 * Run this AFTER `npm run seed` so Firestore holds the full taxonomy.
 * On-device first-launch uses this bundle to populate the catalog without
 * hitting Firestore; subsequent runs layer Firestore reads on top for
 * freshness.
 *
 *   npm run export-seed -- --region AU
 */
import "dotenv/config";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname, join } from "path";

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

const region = parseArg("region") ?? "AU";
const outPath = parseArg("out")
  ?? join("..", "..", "BirdPokemon", "Resources", "Seeds", `taxonomy_${region}.json`);

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

// Mirrors the Swift `Species` model (BirdPokemon/Models/Species.swift).
// Only shippable-offline fields go in the bundle — heavy fields like
// `wikipediaURL` can stay Firestore-only.
type BundledSpecies = {
  ebirdCode: string;
  commonName: string;
  scientificName: string;
  order: string;
  family: string;
  familyCommonName?: string | null;
  sizeCategory: string;
  primaryColors: string[];
  regionCodes: string[];
  thumbnailURL?: string | null;
  ebirdURL?: string | null;
};

async function main() {
  console.log(`Exporting region ${region} from project ${process.env.FIREBASE_PROJECT_ID}…`);
  // No orderBy — avoids requiring a deployed composite index just to export.
  // Sort in memory after the fetch (region lists are <1000 docs each).
  const snap = await db
    .collection("speciesCache")
    .where("regionCodes", "array-contains", region)
    .get();

  const bundled: BundledSpecies[] = snap.docs
    .map((doc) => {
      const d = doc.data();
      return {
        ebirdCode: d.ebirdCode,
        commonName: d.commonName,
        scientificName: d.scientificName,
        order: d.order,
        family: d.family,
        familyCommonName: d.familyCommonName ?? null,
        sizeCategory: d.sizeCategory ?? "medium",
        primaryColors: d.primaryColors ?? [],
        regionCodes: d.regionCodes ?? [region],
        thumbnailURL: d.thumbnailURL ?? null,
        ebirdURL: d.ebirdURL ?? null,
      };
    })
    .sort((a, b) => a.commonName.localeCompare(b.commonName));

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(bundled, null, 2) + "\n");
  console.log(`Wrote ${bundled.length} species to ${outPath}`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
