/**
 * Shared helpers for the bundled per-region taxonomy JSON
 * (`DownUnderBirdCollector/Resources/Seeds/taxonomy_<REGION>.json`).
 *
 * That file is the single source of truth for species data: the iOS app and
 * the web app both read it directly, and `seed.ts` mirrors it into Firestore.
 * Every script that writes it goes through `writeBundle`, which normalises
 * records so they always decode on device.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Must match `BirdColor` (iOS) and `COLORS` (web).
export const COLORS = [
  "red", "orange", "yellow", "green", "blue", "brown",
  "black", "white", "gray", "pink", "purple",
] as const;
export type BirdColor = (typeof COLORS)[number];

// Must match `SizeCategory` (iOS) and `SIZES` (web).
export const SIZES = ["tiny", "small", "medium", "large", "huge"] as const;
export type SizeCategory = (typeof SIZES)[number];

/** Plumage words that show up in field guides, folded onto the app's palette. */
export const COLOR_ALIASES: Record<string, BirdColor | null> = {
  grey: "gray",
  buff: "brown",
  rufous: "orange",
  chestnut: "brown",
  tawny: "brown",
  cinnamon: "brown",
  olive: "green",
  bronze: "green",
  crimson: "red",
  scarlet: "red",
  gold: "yellow",
  plum: "purple",
  violet: "purple",
  // Patterns, not colours.
  streaked: null,
  barred: null,
  spotted: null,
};

export type BundledSpecies = {
  ebirdCode: string;
  commonName: string;
  scientificName: string;
  order: string;
  family: string;
  familyCommonName: string | null;
  category: string;
  sizeCategory: SizeCategory;
  primaryColors: BirdColor[];
  regionCodes: string[];
  thumbnailURL: string | null;
  thumbnailAttribution: string | null;
  thumbnailLicense: string | null;
  /** A recording of its call/song, played by "Hear its call". */
  callURL: string | null;
  callAttribution: string | null;
  callLicense: string | null;
  callSource: "xeno-canto" | "inaturalist" | null;
  callPageURL: string | null;
  wikipediaURL: string | null;
  ebirdURL: string;
};

const here = dirname(fileURLToPath(import.meta.url));
export const SEEDS_DIR = resolve(here, "../../../DownUnderBirdCollector/Resources/Seeds");

export function bundlePath(region: string): string {
  return resolve(SEEDS_DIR, `taxonomy_${region.toUpperCase()}.json`);
}

export function bundleExists(region: string): boolean {
  return existsSync(bundlePath(region));
}

export function readBundle(region: string): BundledSpecies[] {
  const raw = JSON.parse(readFileSync(bundlePath(region), "utf-8")) as Record<string, unknown>[];
  return raw.map((r) => normalizeSpecies(r).species);
}

export function readBundleRaw(region: string): Record<string, unknown>[] {
  return JSON.parse(readFileSync(bundlePath(region), "utf-8"));
}

export function writeBundle(region: string, species: BundledSpecies[]): string {
  const path = bundlePath(region);
  const normalized = species.map((s) => normalizeSpecies(s).species);
  writeFileSync(path, JSON.stringify(normalized, null, 2) + "\n");
  return path;
}

export function normalizeColor(value: string): BirdColor | null {
  const key = value.trim().toLowerCase();
  if ((COLORS as readonly string[]).includes(key)) return key as BirdColor;
  if (key in COLOR_ALIASES) return COLOR_ALIASES[key];
  return null;
}

/**
 * Coerce a raw record into a valid `BundledSpecies`. Returns the warnings
 * raised while doing so; `validate-bundle.ts` treats those as errors unless
 * run with `--fix`.
 */
export function normalizeSpecies(raw: Record<string, unknown>): {
  species: BundledSpecies;
  warnings: string[];
} {
  const warnings: string[] = [];
  const str = (key: string): string => {
    const v = raw[key];
    if (typeof v !== "string" || v.trim() === "") {
      warnings.push(`missing ${key}`);
      return "";
    }
    return v;
  };
  const optStr = (key: string): string | null => {
    const v = raw[key];
    return typeof v === "string" && v.trim() !== "" ? v : null;
  };

  const code = str("ebirdCode");

  const colors: BirdColor[] = [];
  for (const c of (raw.primaryColors as unknown[]) ?? []) {
    if (typeof c !== "string") continue;
    const mapped = normalizeColor(c);
    if (mapped === null) {
      warnings.push(`dropped colour "${c}"`);
    } else {
      if (mapped !== c) warnings.push(`colour "${c}" -> "${mapped}"`);
      if (!colors.includes(mapped)) colors.push(mapped);
    }
  }

  let size = raw.sizeCategory as string;
  if (!(SIZES as readonly string[]).includes(size)) {
    warnings.push(`size "${size}" -> "medium"`);
    size = "medium";
  }

  const regions = Array.isArray(raw.regionCodes)
    ? (raw.regionCodes as unknown[]).filter((r): r is string => typeof r === "string")
    : [];
  if (regions.length === 0) warnings.push("no regionCodes");

  return {
    warnings,
    species: {
      ebirdCode: code,
      commonName: str("commonName"),
      scientificName: str("scientificName"),
      order: str("order"),
      family: str("family"),
      familyCommonName: optStr("familyCommonName"),
      category: optStr("category") ?? "species",
      sizeCategory: size as SizeCategory,
      primaryColors: colors,
      regionCodes: regions,
      thumbnailURL: optStr("thumbnailURL"),
      thumbnailAttribution: optStr("thumbnailAttribution"),
      thumbnailLicense: optStr("thumbnailLicense"),
      callURL: optStr("callURL"),
      callAttribution: optStr("callAttribution"),
      callLicense: optStr("callLicense"),
      callSource: (["xeno-canto", "inaturalist"].includes(raw.callSource as string) ? raw.callSource : null) as BundledSpecies["callSource"],
      callPageURL: optStr("callPageURL"),
      wikipediaURL: optStr("wikipediaURL"),
      ebirdURL: optStr("ebirdURL") ?? `https://ebird.org/species/${code}`,
    },
  };
}

/** `--name value` style CLI argument. */
export function parseArg(name: string): string | undefined {
  const idx = process.argv.indexOf(`--${name}`);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

export function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

export function bucketSize(lengthCm: number | null | undefined): SizeCategory | null {
  if (lengthCm == null || !Number.isFinite(lengthCm)) return null;
  if (lengthCm < 10) return "tiny";
  if (lengthCm < 20) return "small";
  if (lengthCm < 35) return "medium";
  if (lengthCm < 60) return "large";
  return "huge";
}
