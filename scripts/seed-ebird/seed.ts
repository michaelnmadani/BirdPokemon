/**
 * Mirror a bundled taxonomy file into Firestore `speciesCache`.
 *
 * Only needed if you turn on cloud sync and want species data server-side
 * (e.g. for a future web dashboard). The apps themselves read the bundled
 * JSON and never depend on this collection.
 *
 * Usage:
 *   npm run seed -- --region AU [--dry-run]
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS (service-account JSON path) and
 * FIREBASE_PROJECT_ID in .env.
 */
import "dotenv/config";
import { readFileSync } from "node:fs";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { hasFlag, parseArg, readBundle } from "./lib/bundle.ts";

const region = (parseArg("region") ?? "AU").toUpperCase();
const dryRun = hasFlag("dry-run");

async function main() {
  const species = readBundle(region);
  console.log(`${species.length} ${region} species in the bundle.`);
  if (dryRun) {
    console.log("DRY RUN — not writing to Firestore.");
    return;
  }

  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS ?? "./service-account.json";
  initializeApp({
    credential: cert(JSON.parse(readFileSync(credentialsPath, "utf-8"))),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
  const db = getFirestore();

  // BulkWriter batches, retries and throttles on its own — no 500-write limit.
  const writer = db.bulkWriter();
  for (const s of species) {
    const { regionCodes, ...rest } = s;
    writer.set(
      db.collection("speciesCache").doc(s.ebirdCode),
      { ...rest, regionCodes: FieldValue.arrayUnion(...regionCodes), updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  }
  await writer.close();
  console.log(`Wrote ${species.length} documents to speciesCache.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
