// Pure helpers for photo identification (no browser APIs), so they run under
// node --test. Mirrors PhotoIDCore.swift on iOS.
//
// The model (MobileNet V2 trained on iNaturalist bird photos, Google, Apache-2.0)
// knows ~960 species worldwide, of which 77 are in the Australian field guide:
// it only ever suggests those, and the user always confirms.

export const INPUT_SIZE = 224;
export const MIN_CONFIDENCE = 0.05;
export const MAX_SUGGESTIONS = 3;

/** "Dacelo novaeguineae (Laughing Kookaburra)" lines -> [{ sci, common }] ("background" has no common name). */
export function parseLabels(text) {
  return text.split(/\r?\n/).filter((l) => l.trim()).map((line) => {
    const m = line.trim().match(/^(.+?) \((.+)\)$/);
    return m ? { sci: m[1], common: m[2] } : { sci: line.trim(), common: '' };
  });
}

/** Genus + species epithet without its Latin gender ending ("moluccus" ~ "molucca"). */
export function latinStem(sci) {
  const [genus, epithet = ''] = sci.toLowerCase().split(/\s+/);
  return `${genus} ${epithet.replace(/(us|um|a|is|e)$/, '')}`;
}

const words = (name) => new Set(name.toLowerCase().match(/[a-z]+/g) ?? []);

/**
 * For each model class, the matching field-guide species code or null: by
 * scientific name, then common name, then the same Latin stem when the
 * common names share a word (Australian Ibis ~ Australian White Ibis).
 */
export function mapLabels(labels, catalogSpecies) {
  const bySci = new Map();
  const byCommon = new Map();
  const byStem = new Map();
  for (const s of catalogSpecies) {
    bySci.set(s.scientificName.toLowerCase(), s);
    byCommon.set(s.commonName.toLowerCase(), s);
    byStem.set(latinStem(s.scientificName), s);
  }
  return labels.map(({ sci, common }) => {
    const exact = bySci.get(sci.toLowerCase()) ?? (common && byCommon.get(common.toLowerCase()));
    if (exact) return exact.ebirdCode;
    const stem = byStem.get(latinStem(sci));
    const shared = stem && [...words(common)].some((w) => words(stem.commonName).has(w));
    return shared ? stem.ebirdCode : null;
  });
}

/** Model output (uint8, scale 1/256) -> probabilities. */
export function dequantize(bytes) {
  return Float32Array.from(bytes, (b) => b / 256);
}

/**
 * Field-guide suggestions from the model's probabilities, best first:
 * { suggestions: [{ code, confidence }], unsure } — `unsure` when the model's
 * overall best guess is a bird that isn't in the field guide (so it may simply
 * not know this one).
 */
export function suggestions(probs, codes, { min = MIN_CONFIDENCE, max = MAX_SUGGESTIONS } = {}) {
  let best = 0;
  let bestKnown = 0;
  const found = [];
  for (let i = 0; i < probs.length; i++) {
    best = Math.max(best, probs[i]);
    if (!codes[i]) continue;
    bestKnown = Math.max(bestKnown, probs[i]);
    if (probs[i] >= min) found.push({ code: codes[i], confidence: probs[i] });
  }
  found.sort((a, b) => b.confidence - a.confidence);
  // Several classes can map to one species; keep the best of each.
  const seen = new Set();
  const unique = found.filter((s) => !seen.has(s.code) && seen.add(s.code));
  return { suggestions: unique.slice(0, max), unsure: best > bestKnown };
}

/** Centre square of a width × height image: { sx, sy, size }. */
export function centreSquare(width, height) {
  const size = Math.min(width, height);
  return { sx: Math.floor((width - size) / 2), sy: Math.floor((height - size) / 2), size };
}
