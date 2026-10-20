// Species model and filtering shared by every screen. Pure functions only so
// they run under `node --test` as well as in the browser.

// Must match BirdColor (iOS) and COLORS in scripts/seed-ebird/lib/bundle.ts.
export const COLORS = {
  red: '#d93a2b',
  orange: '#ef8a1f',
  yellow: '#f4cf2f',
  green: '#3a9b4a',
  blue: '#2f6fd6',
  brown: '#8c5a2e',
  black: '#1b1b1d',
  white: '#ffffff',
  gray: '#9a9a9f',
  pink: '#ec7fb0',
  purple: '#8a4fc0',
};

export const COLOR_ALIASES = {
  grey: 'gray', buff: 'brown', rufous: 'orange', chestnut: 'brown', tawny: 'brown',
  cinnamon: 'brown', olive: 'green', bronze: 'green', crimson: 'red', scarlet: 'red',
  gold: 'yellow', plum: 'purple', violet: 'purple',
};

export const SIZES = [
  { id: 'tiny', label: 'Tiny', length: '< 10 cm' },
  { id: 'small', label: 'Small', length: '10 – 20 cm' },
  { id: 'medium', label: 'Medium', length: '20 – 35 cm' },
  { id: 'large', label: 'Large', length: '35 – 60 cm' },
  { id: 'huge', label: 'Huge', length: '> 60 cm' },
];

export const REGIONS = {
  AU: { name: 'Australia', flag: '🇦🇺' },
  NZ: { name: 'New Zealand', flag: '🇳🇿' },
  GB: { name: 'United Kingdom', flag: '🇬🇧' },
  US: { name: 'United States', flag: '🇺🇸' },
};

export function normalizeColor(value) {
  const key = String(value).trim().toLowerCase();
  if (key in COLORS) return key;
  return COLOR_ALIASES[key] ?? null;
}

/** Lenient decode, mirroring Species.init(from:) on iOS. Returns null if unusable. */
export function normalizeSpecies(raw) {
  if (!raw || typeof raw.ebirdCode !== 'string' || typeof raw.commonName !== 'string') return null;
  const colors = [];
  for (const c of raw.primaryColors ?? []) {
    const mapped = normalizeColor(c);
    if (mapped && !colors.includes(mapped)) colors.push(mapped);
  }
  return {
    ebirdCode: raw.ebirdCode,
    commonName: raw.commonName,
    scientificName: raw.scientificName ?? '',
    order: raw.order ?? '',
    family: raw.family ?? 'Unknown',
    familyCommonName: raw.familyCommonName ?? null,
    familyDisplayName: raw.familyCommonName ?? raw.family ?? 'Unknown',
    sizeCategory: SIZES.some((s) => s.id === raw.sizeCategory) ? raw.sizeCategory : 'medium',
    primaryColors: colors,
    regionCodes: Array.isArray(raw.regionCodes) ? raw.regionCodes : [],
    thumbnailURL: raw.thumbnailURL ?? null,
    thumbnailAttribution: raw.thumbnailAttribution ?? null,
    thumbnailLicense: raw.thumbnailLicense ?? null,
    ebirdURL: raw.ebirdURL ?? `https://ebird.org/species/${raw.ebirdCode}`,
    wikipediaURL: raw.wikipediaURL ?? null,
  };
}

export function sizeInfo(id) {
  return SIZES.find((s) => s.id === id) ?? SIZES[2];
}

/** "cc-by-nc" -> "CC BY-NC" */
export function licenceLabel(code) {
  return code ? code.toUpperCase().replace('CC-', 'CC ') : null;
}

export function photoCredit(species) {
  const parts = [species.thumbnailAttribution, licenceLabel(species.thumbnailLicense)].filter(Boolean);
  return parts.length ? parts.join(' · ') : null;
}

export function emptyCriteria() {
  return { sizes: new Set(), colors: new Set(), families: new Set(), search: '' };
}

export function activeFilterCount(c) {
  return [c.sizes, c.colors, c.families].filter((s) => s.size > 0).length;
}

/** Same rules as FilterCriteria.matches on iOS. */
export function matches(c, species) {
  if (c.sizes.size && !c.sizes.has(species.sizeCategory)) return false;
  if (c.colors.size && !species.primaryColors.some((col) => c.colors.has(col))) return false;
  if (c.families.size && !c.families.has(species.family)) return false;
  const needle = c.search.trim().toLowerCase();
  if (needle) {
    const hay = `${species.commonName} ${species.scientificName} ${species.familyDisplayName} ${species.groupText ?? ''}`.toLowerCase();
    if (!hay.includes(needle)) return false;
  }
  return true;
}

export function familyOptions(species) {
  const seen = new Map();
  for (const s of species) if (!seen.has(s.family)) seen.set(s.family, s.familyDisplayName);
  return [...seen].map(([family, label]) => ({ family, label })).sort((a, b) => a.label.localeCompare(b.label));
}

/** Codes of species with at least one sighting. */
export function collectedCodes(sightings) {
  return new Set(sightings.map((s) => s.speciesCode));
}

export function latestBySpecies(sightings) {
  const latest = new Map();
  for (const s of sightings) {
    const current = latest.get(s.speciesCode);
    if (!current || current.capturedAt < s.capturedAt) latest.set(s.speciesCode, s);
  }
  return latest;
}
