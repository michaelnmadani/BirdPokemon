// Pure helpers for BirdNET sound identification (no browser APIs), so they
// run under node --test. Mirrors SoundIDCore.swift on iOS.

export const SAMPLE_RATE = 48000;
export const WINDOW = 3 * SAMPLE_RATE; // BirdNET V2.4 listens to 3-second chunks
export const MIN_CONFIDENCE = 0.25;    // BirdNET's own default threshold

/** "Dacelo novaeguineae_Laughing Kookaburra" lines -> [{ sci, common, isBird }] */
export function parseLabels(text) {
  return text.split(/\r?\n/).filter(Boolean).map((line) => {
    const [sci, common = sci] = line.split('_');
    // Non-bird classes ("Engine_Engine", "Dog_Dog") repeat the same name.
    return { sci: sci.trim(), common: common.trim(), isBird: sci.trim() !== common.trim() };
  });
}

/**
 * For each BirdNET class, the matching field-guide species code (by
 * scientific name, then by common name where the taxonomies differ) or null.
 */
export function mapLabels(labels, catalogSpecies) {
  const bySci = new Map();
  const byCommon = new Map();
  for (const s of catalogSpecies) {
    bySci.set(s.scientificName.toLowerCase(), s.ebirdCode);
    byCommon.set(s.commonName.toLowerCase(), s.ebirdCode);
  }
  return labels.map((l) => (l.isBird
    ? bySci.get(l.sci.toLowerCase()) ?? byCommon.get(l.common.toLowerCase()) ?? null
    : null));
}

/** BirdNET's flat sigmoid: logits -> confidences in 0…1. */
export function sigmoid(x) {
  return 1 / (1 + Math.exp(-Math.max(-15, Math.min(15, x))));
}

/**
 * Classes above `min` in one window, best first.
 * `allowed(index)` decides which classes count (e.g. field-guide birds only).
 */
export function detections(logits, { min = MIN_CONFIDENCE, allowed = () => true } = {}) {
  const out = [];
  for (let i = 0; i < logits.length; i++) {
    if (!allowed(i)) continue;
    const p = sigmoid(logits[i]);
    if (p >= min) out.push({ index: i, confidence: p });
  }
  return out.sort((a, b) => b.confidence - a.confidence);
}

/** Average channels to mono. */
export function mixToMono(channels) {
  if (channels.length === 1) return channels[0];
  const out = new Float32Array(channels[0].length);
  for (const ch of channels) for (let i = 0; i < out.length; i++) out[i] += ch[i] / channels.length;
  return out;
}

/** Linear-interpolation resample (used when the device won't record at 48 kHz). */
export function resample(samples, fromRate, toRate = SAMPLE_RATE) {
  if (fromRate === toRate) return samples;
  const ratio = fromRate / toRate;
  const out = new Float32Array(Math.floor(samples.length / ratio));
  for (let i = 0; i < out.length; i++) {
    const pos = i * ratio;
    const j = Math.floor(pos);
    const frac = pos - j;
    out[i] = samples[j] * (1 - frac) + (samples[j + 1] ?? samples[j]) * frac;
  }
  return out;
}

/** Split audio into 3-second windows; a short tail is zero-padded if at least 1 s long. */
export function windows(samples, size = WINDOW) {
  const out = [];
  for (let start = 0; start < samples.length; start += size) {
    const chunk = samples.subarray(start, start + size);
    if (chunk.length === size) out.push({ start, samples: chunk });
    else if (chunk.length >= SAMPLE_RATE) {
      const padded = new Float32Array(size);
      padded.set(chunk);
      out.push({ start, samples: padded });
    }
  }
  return out;
}

/**
 * Running tally of what's been heard in a session:
 * Map<labelIndex, { index, best, count, firstAt, lastAt }> (times in seconds).
 */
export function addToTally(tally, found, atSeconds) {
  for (const d of found) {
    const entry = tally.get(d.index) ?? { index: d.index, best: 0, count: 0, firstAt: atSeconds, lastAt: atSeconds };
    entry.best = Math.max(entry.best, d.confidence);
    entry.count += 1;
    entry.lastAt = atSeconds;
    tally.set(d.index, entry);
  }
  return tally;
}

export function rankTally(tally) {
  return [...tally.values()].sort((a, b) => b.best - a.best || b.count - a.count);
}
