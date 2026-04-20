/**
 * Enrich speciesCache with:
 *   - sizeCategory bucketed from AVONET body length (CC-BY-4.0).
 *   - primaryColors from a hand-tagged JSON file.
 *
 * Usage:
 *   npm run enrich -- --region AU --avonet ./data/AVONET.csv --colors ./data/colors_AU.json
 */
import "dotenv/config";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { readFileSync } from "fs";

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

const region = parseArg("region") ?? "AU";
const avonetPath = parseArg("avonet");
const colorsPath = parseArg("colors");

if (!avonetPath || !colorsPath) {
  console.error("Usage: --region AU --avonet AVONET.csv --colors colors_AU.json");
  process.exit(1);
}

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

function bucket(lengthCm: number | null): string {
  if (lengthCm == null) return "medium";
  if (lengthCm < 10) return "tiny";
  if (lengthCm < 20) return "small";
  if (lengthCm < 35) return "medium";
  if (lengthCm < 60) return "large";
  return "huge";
}

function parseAvonetLengths(csv: string): Record<string, number> {
  const lines = csv.split(/\r?\n/).filter(Boolean);
  const header = lines[0].split(",");
  const sciCol = header.indexOf("Species1");
  const lengthCol = header.indexOf("Wing.Length");
  if (sciCol < 0 || lengthCol < 0) {
    throw new Error("AVONET CSV missing Species1 or Wing.Length columns");
  }
  const out: Record<string, number> = {};
  for (const line of lines.slice(1)) {
    const cols = line.split(",");
    const sci = cols[sciCol]?.trim();
    const mm = parseFloat(cols[lengthCol]);
    if (sci && Number.isFinite(mm)) {
      // Wing length in mm; body length approximation is ~2x wing length.
      out[sci] = (mm * 2) / 10;
    }
  }
  return out;
}

async function main() {
  const avonet = parseAvonetLengths(readFileSync(avonetPath!, "utf-8"));
  const colors: Record<string, string[]> = JSON.parse(readFileSync(colorsPath!, "utf-8"));

  const snap = await db
    .collection("speciesCache")
    .where("regionCodes", "array-contains", region)
    .get();

  console.log(`Enriching ${snap.size} species for ${region}…`);
  const writer = db.bulkWriter();
  for (const doc of snap.docs) {
    const data = doc.data();
    const sci = data.scientificName as string;
    const length = avonet[sci] ?? null;
    writer.set(
      doc.ref,
      {
        sizeCategory: bucket(length),
        primaryColors: colors[data.ebirdCode] ?? data.primaryColors ?? [],
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
