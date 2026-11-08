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

// ---- AMR recordings (Android voice recorders, phone calls) -------------------
// Browsers can't decode AMR, so js/soundid.js decodes it with opencore-amr.

const AMR_NB_MAGIC = '#!AMR\n';
const AMR_WB_MAGIC = '#!AMR-WB\n';

const ascii = (bytes, start, length) => String.fromCharCode(...bytes.subarray(start, start + length));

/** 'nb' / 'wb' for a raw .amr file, else null. */
export function amrKind(bytes) {
  if (ascii(bytes, 0, AMR_WB_MAGIC.length) === AMR_WB_MAGIC) return 'wb';
  if (ascii(bytes, 0, AMR_NB_MAGIC.length) === AMR_NB_MAGIC) return 'nb';
  return null;
}

/** Child boxes of an ISO-BMFF (MP4/3GP) box payload: [{ type, start, end }]. */
function boxes(view, start, end) {
  const out = [];
  let pos = start;
  while (pos + 8 <= end) {
    let size = view.getUint32(pos);
    const type = ascii(new Uint8Array(view.buffer, view.byteOffset), pos + 4, 4);
    let header = 8;
    if (size === 1) {
      size = Number(view.getBigUint64(pos + 8));
      header = 16;
    } else if (size === 0) {
      size = end - pos;
    }
    if (size < header || pos + size > end) break;
    out.push({ type, start: pos + header, end: pos + size });
    pos += size;
  }
  return out;
}

const child = (view, box, type) => boxes(view, box.start, box.end).find((b) => b.type === type);

/**
 * The AMR track of a 3GP/3GA file (what many Android recorders save) as a
 * plain .amr file, or null if there isn't one.
 */
export function amrFrom3gp(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const moov = boxes(view, 0, bytes.length).find((b) => b.type === 'moov');
  if (!moov) return null;
  for (const trak of boxes(view, moov.start, moov.end).filter((b) => b.type === 'trak')) {
    const stbl = ['mdia', 'minf', 'stbl'].reduce((box, type) => box && child(view, box, type), trak);
    const stsd = stbl && child(view, stbl, 'stsd');
    if (!stsd) continue;
    const entry = boxes(view, stsd.start + 8, stsd.end)[0]; // skip version/flags + entry count
    const kind = { samr: 'nb', sawb: 'wb' }[entry?.type];
    if (!kind) continue;

    const stsz = child(view, stbl, 'stsz');
    const stsc = child(view, stbl, 'stsc');
    const stco = child(view, stbl, 'stco') ?? child(view, stbl, 'co64');
    if (!stsz || !stsc || !stco) return null;

    const fixedSize = view.getUint32(stsz.start + 4);
    const sampleCount = view.getUint32(stsz.start + 8);
    const sizes = Array.from({ length: sampleCount }, (_, i) => fixedSize || view.getUint32(stsz.start + 12 + i * 4));
    const is64 = stco.type === 'co64';
    const chunkCount = view.getUint32(stco.start + 4);
    const chunkOffsets = Array.from({ length: chunkCount }, (_, i) => (is64
      ? Number(view.getBigUint64(stco.start + 8 + i * 8))
      : view.getUint32(stco.start + 8 + i * 4)));
    const runs = Array.from({ length: view.getUint32(stsc.start + 4) }, (_, i) => ({
      firstChunk: view.getUint32(stsc.start + 8 + i * 12),
      samplesPerChunk: view.getUint32(stsc.start + 12 + i * 12),
    }));

    const header = new TextEncoder().encode(kind === 'wb' ? AMR_WB_MAGIC : AMR_NB_MAGIC);
    const total = sizes.reduce((a, b) => a + b, 0);
    const out = new Uint8Array(header.length + total);
    out.set(header);
    let written = header.length;
    let sample = 0;
    for (let chunk = 1; chunk <= chunkCount && sample < sampleCount; chunk++) {
      const run = runs.findLast((r) => r.firstChunk <= chunk);
      let offset = chunkOffsets[chunk - 1];
      for (let i = 0; i < (run?.samplesPerChunk ?? 0) && sample < sampleCount; i++, sample++) {
        if (offset + sizes[sample] > bytes.length) return null;
        out.set(bytes.subarray(offset, offset + sizes[sample]), written);
        written += sizes[sample];
        offset += sizes[sample];
      }
    }
    return out.subarray(0, written);
  }
  return null;
}
