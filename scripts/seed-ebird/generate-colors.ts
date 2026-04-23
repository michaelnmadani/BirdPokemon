/**
 * Generate a starter `colors_<REGION>.json` by matching common names from the
 * seeded Firestore `speciesCache` against a built-in color dictionary.
 *
 * Why this instead of a hand-written JSON? eBird 6-letter species codes are
 * hard to memorise; common names are stable and easy to audit. This script
 * keys by common name, then reads the correct eBird code out of Firestore
 * so the resulting JSON plugs straight into `enrich.ts`.
 *
 * Unmatched species get an empty array — the filter-by-color UI won't match
 * them until someone hand-tags them. Adding species later is a two-step
 * edit here + re-run.
 *
 *   npm run generate-colors -- --region AU
 *   # writes scripts/seed-ebird/data/colors_AU.json
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
const outPath = parseArg("out") ?? join("data", `colors_${region}.json`);

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

// Color dictionary keyed by lowercased, whitespace-normalised common name.
// Values are BirdColor enum rawValues (see BirdPokemon/Models/BirdColor.swift).
//
// AU-focused. Confidence is moderate — verify with a photo search for any
// species before treating this as authoritative. Species not listed get an
// empty array and can be filled in manually.
const COLORS_BY_COMMON_NAME: Record<string, string[]> = {
  "australian magpie": ["black", "white"],
  "laughing kookaburra": ["brown", "white", "blue"],
  "rainbow lorikeet": ["green", "blue", "red", "orange", "yellow"],
  "galah": ["pink", "gray"],
  "sulphur-crested cockatoo": ["white", "yellow"],
  "little corella": ["white", "pink"],
  "long-billed corella": ["white", "pink"],
  "red-tailed black-cockatoo": ["black", "red"],
  "yellow-tailed black-cockatoo": ["black", "yellow"],
  "gang-gang cockatoo": ["gray", "red"],
  "cockatiel": ["gray", "yellow", "orange", "white"],
  "willie wagtail": ["black", "white"],
  "magpie-lark": ["black", "white"],
  "superb fairywren": ["blue", "black", "brown"],
  "splendid fairywren": ["blue", "black"],
  "red-backed fairywren": ["red", "black"],
  "australian raven": ["black"],
  "little raven": ["black"],
  "torresian crow": ["black"],
  "pied currawong": ["black", "white"],
  "grey currawong": ["gray", "white"],
  "noisy miner": ["gray", "yellow", "white", "black"],
  "common myna": ["brown", "yellow", "black"],
  "red wattlebird": ["gray", "brown", "yellow", "red"],
  "new holland honeyeater": ["black", "white", "yellow"],
  "white-plumed honeyeater": ["yellow", "green", "white"],
  "eastern spinebill": ["black", "white", "brown", "red"],
  "silvereye": ["green", "gray", "white"],
  "welcome swallow": ["blue", "orange", "brown"],
  "tree martin": ["blue", "white"],
  "crimson rosella": ["red", "blue", "black"],
  "eastern rosella": ["red", "yellow", "green", "blue", "white"],
  "pale-headed rosella": ["blue", "yellow", "white"],
  "australian king-parrot": ["red", "green", "blue"],
  "red-rumped parrot": ["green", "yellow", "red"],
  "red-winged parrot": ["green", "red", "blue", "black"],
  "budgerigar": ["green", "yellow", "black"],
  "australian ringneck": ["green", "yellow", "blue"],
  "tawny frogmouth": ["brown", "gray"],
  "emu": ["brown"],
  "southern cassowary": ["black", "blue", "red"],
  "australian white ibis": ["white", "black"],
  "straw-necked ibis": ["black", "white", "yellow"],
  "royal spoonbill": ["white", "black"],
  "masked lapwing": ["black", "white", "brown", "yellow"],
  "pacific black duck": ["brown", "green"],
  "chestnut teal": ["brown", "green"],
  "grey teal": ["gray", "brown"],
  "australian wood duck": ["brown", "gray"],
  "black swan": ["black", "red"],
  "magpie goose": ["black", "white"],
  "australasian swamphen": ["blue", "purple", "black", "red"],
  "eurasian coot": ["black", "white"],
  "dusky moorhen": ["black", "red", "yellow"],
  "australasian darter": ["black", "brown"],
  "great cormorant": ["black"],
  "little pied cormorant": ["black", "white"],
  "little black cormorant": ["black"],
  "pied cormorant": ["black", "white"],
  "australian pelican": ["white", "black"],
  "great egret": ["white"],
  "little egret": ["white"],
  "white-faced heron": ["gray", "white"],
  "nankeen night-heron": ["brown", "white"],
  "australasian grebe": ["brown", "black"],
  "wedge-tailed eagle": ["brown", "black"],
  "white-bellied sea-eagle": ["white", "gray"],
  "brown falcon": ["brown"],
  "nankeen kestrel": ["brown", "white"],
  "peregrine falcon": ["gray", "white", "black"],
  "barn owl": ["white", "brown"],
  "southern boobook": ["brown", "white"],
  "powerful owl": ["brown", "white"],
  "pied butcherbird": ["black", "white"],
  "grey butcherbird": ["gray", "white", "black"],
  "black-faced cuckooshrike": ["gray", "black", "white"],
  "olive-backed oriole": ["green", "yellow"],
  "little penguin": ["blue", "white"],
  "common starling": ["black", "purple", "green"],
  "house sparrow": ["brown", "black", "white"],
  "common blackbird": ["black", "orange"],
  "spotted dove": ["brown", "pink", "black"],
  "common bronzewing": ["brown", "green", "purple"],
  "crested pigeon": ["gray", "brown", "green"],
  "rock dove": ["gray"],
  "white-breasted woodswallow": ["gray", "white"],
  "dusky woodswallow": ["brown", "gray"],
  "eastern yellow robin": ["yellow", "gray"],
  "scarlet robin": ["red", "black", "white"],
  "flame robin": ["orange", "gray"],
  "grey fantail": ["gray", "white"],
  "rufous whistler": ["orange", "black", "white"],
  "golden whistler": ["yellow", "black", "white"],
};

function normalise(name: string): string {
  return name.toLowerCase().trim().replace(/\s+/g, " ");
}

async function main() {
  console.log(`Matching colors for ${region} against ${Object.keys(COLORS_BY_COMMON_NAME).length} known species…`);

  const snap = await db
    .collection("speciesCache")
    .where("regionCodes", "array-contains", region)
    .get();

  const out: Record<string, string[]> = {};
  let matched = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const key = normalise(data.commonName ?? "");
    const colors = COLORS_BY_COMMON_NAME[key];
    if (colors) {
      out[data.ebirdCode] = colors;
      matched++;
    }
  }

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(out, null, 2) + "\n");
  console.log(
    `Matched ${matched} / ${snap.size} species. Wrote ${outPath}. ` +
    `Extend COLORS_BY_COMMON_NAME in generate-colors.ts for more.`
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
