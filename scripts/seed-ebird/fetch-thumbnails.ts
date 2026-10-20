/**
 * Pick one CC-licensed iNaturalist photo per species and record its URL,
 * photographer credit and licence in the bundled taxonomy JSON.
 *
 * Usage:
 *   npm run fetch-thumbnails -- --region AU [--limit 20] [--refresh-attribution] [--dry-run]
 *
 *   --limit N               only process the first N species needing work
 *   --refresh-attribution   also revisit species that have a photo but no credit
 *                           (keeps the same photo when iNat still returns it)
 *   --dry-run               print what would change without writing
 */
import { hasFlag, parseArg, readBundle, writeBundle, type BundledSpecies } from "./lib/bundle.ts";
import { DISPLAY_LICENCES, cleanAttribution, observations, photoSize, sleep, type INatPhoto } from "./lib/inat.ts";

const region = (parseArg("region") ?? "AU").toUpperCase();
const limit = parseArg("limit") ? parseInt(parseArg("limit")!, 10) : Infinity;
const refreshAttribution = hasFlag("refresh-attribution");
const dryRun = hasFlag("dry-run");

function photoIdFromUrl(url: string | null): number | null {
  const match = url?.match(/\/photos\/(\d+)\//);
  return match ? Number(match[1]) : null;
}

async function candidatePhotos(scientificName: string): Promise<INatPhoto[]> {
  const data = await observations({
    taxon_name: scientificName,
    quality_grade: "research",
    photos: "true",
    photo_license: DISPLAY_LICENCES.join(","),
    order_by: "votes",
    per_page: "20",
  });
  return data.results.flatMap((obs) => obs.photos).filter((p) => {
    const licence = p.license_code?.toLowerCase();
    return licence && DISPLAY_LICENCES.includes(licence);
  });
}

function needsWork(s: BundledSpecies): boolean {
  if (!s.thumbnailURL) return true;
  return refreshAttribution && !s.thumbnailAttribution;
}

async function main() {
  const species = readBundle(region);
  const todo = species.filter(needsWork).slice(0, limit);
  console.log(`${todo.length} of ${species.length} ${region} species need a photo or credit.`);
  if (dryRun) console.log("DRY RUN — nothing will be written.\n");

  let updated = 0;
  let failed = 0;
  for (const [i, sp] of todo.entries()) {
    process.stdout.write(`[${i + 1}/${todo.length}] ${sp.commonName} (${sp.scientificName}) … `);
    try {
      const photos = await candidatePhotos(sp.scientificName);
      const currentId = photoIdFromUrl(sp.thumbnailURL);
      const chosen = photos.find((p) => p.id === currentId) ?? photos[0];
      if (!chosen) {
        failed++;
        console.log("✗ no CC photo found");
      } else {
        sp.thumbnailURL = photoSize(chosen.url, "medium");
        sp.thumbnailAttribution = cleanAttribution(chosen.attribution);
        sp.thumbnailLicense = chosen.license_code?.toLowerCase() ?? null;
        updated++;
        console.log(`✓ ${sp.thumbnailAttribution ?? "(no credit)"} [${sp.thumbnailLicense}]`);
      }
    } catch (err) {
      failed++;
      console.log(`✗ ${err}`);
    }
    // iNaturalist asks API users to stay around 1 request per second.
    await sleep(1000);
  }

  console.log(`\n${updated} updated, ${failed} without a usable photo.`);
  if (!dryRun && updated > 0) {
    console.log(`Wrote ${writeBundle(region, species)}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
