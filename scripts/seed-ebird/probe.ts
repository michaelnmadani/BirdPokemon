/**
 * One-shot connectivity probe. Verifies the service-account JSON authenticates
 * and that Firestore is reachable from this environment.
 *
 *   npm run probe
 */
import "dotenv/config";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync } from "fs";

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

async function main() {
  console.log(`Project: ${process.env.FIREBASE_PROJECT_ID}`);
  const snap = await db.collection("speciesCache").limit(1).get();
  console.log(`speciesCache exists? size=${snap.size}`);
  if (snap.size > 0) {
    const doc = snap.docs[0].data();
    console.log(`Sample doc: ${doc.ebirdCode} — ${doc.commonName}`);
  } else {
    console.log("speciesCache is empty (seed hasn't run yet, or region not seeded).");
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
