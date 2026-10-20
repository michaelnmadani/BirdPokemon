/**
 * Suggest size categories from AVONET morphology (CC BY 4.0) and apply
 * hand-tagged colours, writing into the bundled taxonomy JSON.
 *
 * Usage:
 *   npm run enrich -- --region AU --avonet ./data/AVONET_eBird.csv [--colors ./data/colors_AU.json] [--write]
 *
 * Export the "AVONET2_eBird" sheet of the AVONET supplement as CSV — its
 * `Species2` names follow the eBird taxonomy, so they match our records.
 *
 * Body length isn't in AVONET, so it's estimated as wing + tail + beak
 * length, which lands within ~10% of field-guide lengths for most birds.
 * Without --write the script only reports what would change; existing
 * hand-set sizes are kept unless they differ by more than one bucket.
 */
import { readFileSync } from "node:fs";
import { parseCsv } from "./lib/csv.ts";
import { SIZES, bucketSize, hasFlag, normalizeColor, parseArg, readBundle, writeBundle, type BirdColor } from "./lib/bundle.ts";

const region = (parseArg("region") ?? "AU").toUpperCase();
const avonetPath = parseArg("avonet");
const colorsPath = parseArg("colors");
const write = hasFlag("write");

if (!avonetPath && !colorsPath) {
  console.error("Usage: --region AU --avonet AVONET_eBird.csv [--colors colors_AU.json] [--write]");
  process.exit(1);
}

function estimatedLengths(csv: string): Map<string, number> {
  const [header, ...rows] = parseCsv(csv);
  const col = (name: string) => header.findIndex((h) => h.trim() === name);
  const nameCol = col("Species2") >= 0 ? col("Species2") : col("Species1");
  const wing = col("Wing.Length"), tail = col("Tail.Length"), beak = col("Beak.Length_Culmen");
  if (nameCol < 0 || wing < 0) throw new Error("AVONET CSV needs Species2 (or Species1) and Wing.Length columns");

  const out = new Map<string, number>();
  for (const r of rows) {
    const w = parseFloat(r[wing]);
    if (!Number.isFinite(w)) continue;
    const t = tail >= 0 ? parseFloat(r[tail]) : NaN;
    const b = beak >= 0 ? parseFloat(r[beak]) : NaN;
    const mm = Number.isFinite(t) ? w + t + (Number.isFinite(b) ? b : 0) : w * 2;
    out.set(r[nameCol].trim(), mm / 10);
  }
  return out;
}

function main() {
  const species = readBundle(region);
  const lengths = avonetPath ? estimatedLengths(readFileSync(avonetPath, "utf-8")) : new Map<string, number>();
  const colors: Record<string, string[]> = colorsPath ? JSON.parse(readFileSync(colorsPath, "utf-8")) : {};

  let sizeChanges = 0, colorChanges = 0, unmatched = 0;
  for (const s of species) {
    if (avonetPath) {
      const suggested = bucketSize(lengths.get(s.scientificName));
      if (!suggested) {
        unmatched++;
      } else if (suggested !== s.sizeCategory) {
        const gap = Math.abs(SIZES.indexOf(suggested) - SIZES.indexOf(s.sizeCategory));
        console.log(`${s.ebirdCode.padEnd(8)} ${s.sizeCategory} -> ${suggested}${gap > 1 ? "" : " (kept: within one bucket)"}  ${s.commonName}`);
        if (gap > 1) { s.sizeCategory = suggested; sizeChanges++; }
      }
    }
    const tagged = colors[s.ebirdCode];
    if (tagged) {
      const next = [...new Set(tagged.map(normalizeColor).filter((c): c is BirdColor => c !== null))];
      if (next.join() !== s.primaryColors.join()) { s.primaryColors = next; colorChanges++; }
    }
  }

  console.log(`\n${sizeChanges} size change(s), ${colorChanges} colour change(s), ${unmatched} species not in AVONET.`);
  if (write) console.log(`Wrote ${writeBundle(region, species)}`);
  else console.log("Dry run — pass --write to save.");
}

main();
