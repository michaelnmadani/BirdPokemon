/**
 * Pick one Creative Commons recording of each species' call or song for the
 * "Hear its call" button, and record its URL, recordist and licence in the
 * bundled taxonomy JSON.
 *
 * Source: xeno-canto (best quality) when XENO_CANTO_API_KEY is set — get a
 * free key from your xeno-canto account page — otherwise iNaturalist
 * research-grade observations with sound.
 *
 * Usage:
 *   npm run fetch-calls -- --region AU [--limit 20] [--refresh] [--dry-run]
 *
 *   --refresh   replace existing recordings too (e.g. to upgrade to xeno-canto)
 */
import "dotenv/config";
import { hasFlag, parseArg, readBundle, writeBundle, type BundledSpecies } from "./lib/bundle.ts";
import { DISPLAY_LICENCES, USER_AGENT, cleanAttribution, observations, sleep } from "./lib/inat.ts";

const region = (parseArg("region") ?? "AU").toUpperCase();
const limit = parseArg("limit") ? parseInt(parseArg("limit")!, 10) : Infinity;
const refresh = hasFlag("refresh");
const dryRun = hasFlag("dry-run");
const xcKey = process.env.XENO_CANTO_API_KEY?.trim();

type Call = Pick<BundledSpecies, "callURL" | "callAttribution" | "callLicense" | "callSource" | "callPageURL">;

/** "//creativecommons.org/licenses/by-nc-sa/4.0/" -> "cc-by-nc-sa" */
export function licenceFromUrl(url: string): string | null {
  const m = url.match(/licenses\/([a-z-]+)\//i) ?? url.match(/publicdomain\/zero/i);
  if (!m) return null;
  return m[1] ? `cc-${m[1].toLowerCase()}` : "cc0";
}

type XCRecording = { id: string; file: string; lic: string; rec: string; q: string; length: string; type: string };

async function fromXenoCanto(s: BundledSpecies): Promise<Call | null> {
  const [genus, epithet] = s.scientificName.split(/\s+/);
  const url = new URL("https://xeno-canto.org/api/3/recordings");
  url.searchParams.set("query", `gen:${genus} sp:${epithet} q:A`);
  url.searchParams.set("key", xcKey!);
  const resp = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!resp.ok) throw new Error(`xeno-canto ${resp.status}`);
  const data = (await resp.json()) as { recordings: XCRecording[] };
  const seconds = (len: string) => len.split(":").reduce((t, p) => t * 60 + Number(p), 0);
  const usable = data.recordings
    .filter((r) => {
      const lic = licenceFromUrl(r.lic);
      return lic && DISPLAY_LICENCES.includes(lic) && seconds(r.length) >= 4 && seconds(r.length) <= 90;
    })
    .sort((a, b) => seconds(a.length) - seconds(b.length));
  const rec = usable[0];
  if (!rec) return null;
  return {
    callURL: rec.file.startsWith("//") ? `https:${rec.file}` : rec.file,
    callAttribution: rec.rec ? `© ${rec.rec}` : null,
    callLicense: licenceFromUrl(rec.lic),
    callSource: "xeno-canto",
    callPageURL: `https://xeno-canto.org/${rec.id}`,
  };
}

type INatSound = { id: number; file_url: string; license_code?: string | null; attribution?: string | null; file_content_type?: string };

async function fromINaturalist(s: BundledSpecies): Promise<Call | null> {
  const data = await observations({
    taxon_name: s.scientificName,
    quality_grade: "research",
    sounds: "true",
    sound_license: DISPLAY_LICENCES.join(","),
    order_by: "votes",
    per_page: "20",
  });
  for (const obs of data.results as unknown as { id: number; sounds?: INatSound[] }[]) {
    for (const sound of obs.sounds ?? []) {
      const lic = sound.license_code?.toLowerCase();
      if (!sound.file_url || !lic || !DISPLAY_LICENCES.includes(lic)) continue;
      return {
        callURL: sound.file_url,
        callAttribution: cleanAttribution(sound.attribution),
        callLicense: lic,
        callSource: "inaturalist",
        callPageURL: `https://www.inaturalist.org/observations/${obs.id}`,
      };
    }
  }
  return null;
}

async function main() {
  const species = readBundle(region);
  const todo = species.filter((s) => refresh || !s.callURL).slice(0, limit);
  console.log(`${todo.length} ${region} species to look up via ${xcKey ? "xeno-canto" : "iNaturalist"}.`);

  let found = 0;
  for (const [i, s] of todo.entries()) {
    process.stdout.write(`[${i + 1}/${todo.length}] ${s.commonName} … `);
    try {
      const call = (xcKey ? await fromXenoCanto(s) : null) ?? (await fromINaturalist(s));
      if (call) {
        Object.assign(s, call);
        found++;
        console.log(`✓ ${call.callSource} ${call.callAttribution ?? ""} [${call.callLicense}]`);
      } else {
        console.log("✗ none");
      }
    } catch (err) {
      console.log(`✗ ${err}`);
    }
    await sleep(1000);
  }
  console.log(`\n${found} recordings found.`);
  if (!dryRun && found > 0) console.log(`Wrote ${writeBundle(region, species)}`);
}

if (process.argv[1]?.endsWith("fetch-calls.ts")) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
