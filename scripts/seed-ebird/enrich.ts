/**
 * Enrich speciesCache with:
 *   - sizeCategory bucketed from AVONET body length (CC-BY-4.0).
 *   - primaryColors from a hand-tagged JSON file.
 *
 * AVONET source can be CSV or the original Figshare XLSX workbook
 * (auto-detected by extension). The XLSX path looks at the eBird-keyed
 * sheet first (AVONET2_eBird), then falls back to BirdLife or the first
 * sheet that has the expected columns.
 *
 * Usage:
 *   npm run enrich -- --region AU --avonet ./AVONET.xlsx --colors ./data/colors_AU.json
 *   npm run enrich -- --region AU --avonet ./data/AVONET.csv --colors ./data/colors_AU.json
 */
import "dotenv/config";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { readFileSync } from "fs";
import { extname } from "path";
import * as XLSX from "xlsx";

function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

const region = parseArg("region") ?? "AU";
const avonetPath = parseArg("avonet");
const colorsPath = parseArg("colors");

if (!avonetPath || !colorsPath) {
  console.error(
    "Usage: --region AU --avonet AVONET.{csv,xlsx} --colors colors_AU.json"
  );
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

// AVONET sheets use varying column names across taxonomies. We try a few
// candidates so the script works against the original Figshare workbook
// without hand-editing.
const SPECIES_COLUMN_CANDIDATES = ["Species2", "Species1", "Species3", "species"];
const LENGTH_COLUMN_CANDIDATES = [
  "Wing.Length", "Wing Length", "wing.length", "wing_length", "Wing.length",
];

function pickColumn(headers: string[], candidates: string[]): string | undefined {
  for (const c of candidates) {
    if (headers.includes(c)) return c;
  }
  return undefined;
}

function parseAvonetCsv(text: string): Record<string, number> {
  const lines = text.split(/\r?\n/).filter(Boolean);
  const header = lines[0].split(",");
  const sciCol = pickColumn(header, SPECIES_COLUMN_CANDIDATES);
  const lengthCol = pickColumn(header, LENGTH_COLUMN_CANDIDATES);
  if (!sciCol || !lengthCol) {
    throw new Error(
      `AVONET CSV missing species/wing-length columns. Saw: ${header.join(", ")}`
    );
  }
  const sciIdx = header.indexOf(sciCol);
  const lenIdx = header.indexOf(lengthCol);
  const out: Record<string, number> = {};
  for (const line of lines.slice(1)) {
    const cols = line.split(",");
    const sci = cols[sciIdx]?.trim();
    const mm = parseFloat(cols[lenIdx]);
    if (sci && Number.isFinite(mm)) {
      // Wing length in mm; body length approximation is ~2x wing length.
      out[sci] = (mm * 2) / 10;
    }
  }
  return out;
}

function parseAvonetXlsx(buffer: Buffer): Record<string, number> {
  const workbook = XLSX.read(buffer, { type: "buffer" });
  const preferred = ["AVONET2_eBird", "AVONET1_BirdLife", "AVONET3_Howard&Moore"];
  const sheetNames = [
    ...preferred.filter((n) => workbook.SheetNames.includes(n)),
    ...workbook.SheetNames.filter((n) => !preferred.includes(n)),
  ];

  for (const name of sheetNames) {
    const sheet = workbook.Sheets[name];
    const rows = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, {
      defval: null,
    });
    if (rows.length === 0) continue;
    const headers = Object.keys(rows[0]);
    const sciCol = pickColumn(headers, SPECIES_COLUMN_CANDIDATES);
    const lengthCol = pickColumn(headers, LENGTH_COLUMN_CANDIDATES);
    if (!sciCol || !lengthCol) continue;

    console.log(
      `AVONET: reading sheet "${name}" (species column "${sciCol}", length column "${lengthCol}")`
    );
    const out: Record<string, number> = {};
    for (const row of rows) {
      const sci = String(row[sciCol] ?? "").trim();
      const mm = Number(row[lengthCol]);
      if (sci && Number.isFinite(mm)) {
        out[sci] = (mm * 2) / 10;
      }
    }
    return out;
  }

  throw new Error(
    `No AVONET sheet had recognisable columns. Sheets seen: ${workbook.SheetNames.join(", ")}`
  );
}

function loadAvonet(path: string): Record<string, number> {
  if (extname(path).toLowerCase() === ".xlsx") {
    return parseAvonetXlsx(readFileSync(path));
  }
  return parseAvonetCsv(readFileSync(path, "utf-8"));
}

async function main() {
  const avonet = loadAvonet(avonetPath!);
  const colors: Record<string, string[]> = JSON.parse(readFileSync(colorsPath!, "utf-8"));

  const snap = await db
    .collection("speciesCache")
    .where("regionCodes", "array-contains", region)
    .get();

  console.log(`Enriching ${snap.size} species for ${region}…`);
  const writer = db.bulkWriter();
  let sizeMatched = 0;
  let colorMatched = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const sci = data.scientificName as string;
    const length = avonet[sci] ?? null;
    if (length != null) sizeMatched++;
    const docColors = colors[data.ebirdCode];
    if (docColors) colorMatched++;
    writer.set(
      doc.ref,
      {
        sizeCategory: bucket(length),
        primaryColors: docColors ?? data.primaryColors ?? [],
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
  await writer.close();
  console.log(
    `Done. AVONET size matched ${sizeMatched}/${snap.size}; colors matched ${colorMatched}/${snap.size}.`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
