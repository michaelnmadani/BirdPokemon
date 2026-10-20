/**
 * Validate (and optionally repair) a bundled taxonomy file.
 *
 * Usage:
 *   npm run validate -- --region AU          # exit 1 on any problem
 *   npm run validate -- --region AU --fix    # normalise in place
 *
 * Checks: required fields, colour/size values the apps understand, region
 * codes, and duplicate eBird codes. CI runs this so a bad edit can never ship
 * a file the iOS decoder rejects.
 */
import { bundleExists, hasFlag, normalizeSpecies, parseArg, readBundleRaw, writeBundle } from "./lib/bundle.ts";

const fix = hasFlag("fix");
const regions = parseArg("region")
  ? [parseArg("region")!.toUpperCase()]
  : ["AU", "NZ", "GB", "US"].filter(bundleExists);

let problems = 0;

for (const region of regions) {
  const raw = readBundleRaw(region);
  const seen = new Set<string>();
  const out = [];
  let regionProblems = 0;

  for (const record of raw) {
    const { species, warnings } = normalizeSpecies(record);
    const hardErrors = warnings.filter((w) => w.startsWith("missing") || w === "no regionCodes");
    if (seen.has(species.ebirdCode)) hardErrors.push("duplicate ebirdCode");
    seen.add(species.ebirdCode);

    if (warnings.length || hardErrors.length) {
      const all = [...new Set([...warnings, ...hardErrors])];
      console.log(`${region} ${species.ebirdCode || "(no code)"}: ${all.join("; ")}`);
      regionProblems += fix ? hardErrors.length : all.length;
    }
    if (!hardErrors.includes("duplicate ebirdCode")) out.push(species);
  }

  if (fix) {
    writeBundle(region, out);
    console.log(`${region}: wrote ${out.length} species.`);
  }
  console.log(`${region}: ${raw.length} records, ${regionProblems} unresolved problem(s).`);
  problems += regionProblems;
}

if (problems > 0) {
  console.error(fix ? "Some problems need a manual fix." : "Run with --fix to normalise.");
  process.exit(1);
}
