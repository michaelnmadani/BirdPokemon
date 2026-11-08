// BirdNET V2.4 sound identification in the browser, via LiteRT.js (WASM).
// The model (~52 MB) downloads on first use and is kept in Cache Storage,
// so after that it works offline. Model: CC BY-NC-SA 4.0, Cornell Lab of
// Ornithology & Chemnitz University of Technology.
import { SAMPLE_RATE, WINDOW, amrFrom3gp, amrKind, mapLabels, mixToMono, parseLabels, resample } from './soundid-core.js';

export const MODEL_URL = new URL('../models/birdnet/BirdNET_GLOBAL_6K_V2.4_Model_FP32.tflite', import.meta.url).href;
export const LABELS_URL = new URL('../models/birdnet/BirdNET_GLOBAL_6K_V2.4_Labels.txt', import.meta.url).href;
const WASM_DIR = new URL('../vendor/litert/', import.meta.url).href;
export const CACHE_NAME = 'birdnet-v2.4';
export const MODEL_MB = 52;
const MAX_FILE_SECONDS = 10 * 60;

async function cache() {
  return 'caches' in window ? caches.open(CACHE_NAME) : null;
}

/** Is the model part of this build? (false when the build skipped it) */
export async function isAvailable() {
  if (await isDownloaded()) return true;
  try {
    const resp = await fetch(MODEL_URL, { method: 'HEAD' });
    return resp.ok;
  } catch {
    return false;
  }
}

export async function isDownloaded() {
  return Boolean(await (await cache())?.match(MODEL_URL));
}

export async function removeDownload() {
  if ('caches' in window) await caches.delete(CACHE_NAME);
}

/** Fetch with progress, stored in Cache Storage for offline use. */
async function cachedBytes(url, onProgress) {
  const store = await cache();
  const hit = await store?.match(url);
  if (hit) return new Uint8Array(await hit.arrayBuffer());
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`Download failed (${resp.status})`);
  const total = Number(resp.headers.get('content-length')) || 0;
  const reader = resp.body.getReader();
  const parts = [];
  let received = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value);
    received += value.length;
    onProgress?.(total ? received / total : 0);
  }
  const bytes = new Uint8Array(received);
  let offset = 0;
  for (const p of parts) {
    bytes.set(p, offset);
    offset += p.length;
  }
  await store?.put(url, new Response(bytes, { headers: { 'Content-Type': resp.headers.get('content-type') ?? 'application/octet-stream' } }));
  return bytes;
}

export class SoundID {
  /** Loads runtime, model and labels. `catalogSpecies` maps classes to field-guide codes. */
  static async load(catalogSpecies, onProgress) {
    const { loadLiteRt, loadAndCompile, Tensor } = await import('../vendor/litert/litert.js');
    await loadLiteRt(WASM_DIR);
    const [modelBytes, labelBytes] = await Promise.all([
      cachedBytes(MODEL_URL, onProgress),
      cachedBytes(LABELS_URL),
    ]);
    const model = await loadAndCompile(modelBytes, { accelerator: 'wasm' });
    const labels = parseLabels(new TextDecoder().decode(labelBytes));
    return new SoundID(model, Tensor, labels, mapLabels(labels, catalogSpecies));
  }

  constructor(model, Tensor, labels, codes) {
    this.model = model;
    this.Tensor = Tensor;
    this.labels = labels;
    this.codes = codes;
  }

  /** One 3-second, 48 kHz mono window -> raw logits (Float32Array, one per class). */
  async classify(samples) {
    const input = new this.Tensor(samples, [1, WINDOW]);
    try {
      const results = await this.model.run(input);
      const output = await results[0].moveTo('wasm');
      const logits = Float32Array.from(output.toTypedArray());
      output.delete();
      return logits;
    } finally {
      input.delete();
    }
  }
}

const TOO_LONG = 'Recordings longer than 10 minutes aren’t supported.';

/**
 * Decode an audio file to 48 kHz mono: { samples, sourceRate }. `sourceRate`
 * is the recording's own rate — AMR voice recordings are 8 or 16 kHz, so
 * high-pitched calls are missing from them.
 */
export async function decodeFile(file) {
  const bytes = new Uint8Array(await file.arrayBuffer());
  // AMR (raw, or inside the 3GP/3GA files Android recorders make) — browsers can't decode it.
  const amr = amrKind(bytes) ? bytes : (/\.(3gp|3ga|3gpp)$/i.test(file.name) || isIsoMedia(bytes)) ? amrFrom3gp(bytes) : null;
  if (amr) {
    const { default: decodeAmr } = await import('../vendor/amr/decode-amr.js');
    const { channelData, sampleRate } = await decodeAmr(amr);
    if (!channelData.length) throw new Error('The AMR recording has no audio in it.');
    if (channelData[0].length / sampleRate > MAX_FILE_SECONDS) throw new Error(TOO_LONG);
    return { samples: resample(channelData[0], sampleRate), sourceRate: sampleRate };
  }

  const ctx = new OfflineAudioContext(1, 1, SAMPLE_RATE);
  let buffer;
  try {
    buffer = await ctx.decodeAudioData(bytes.buffer);
  } catch {
    const type = file.name.includes('.') ? `.${file.name.split('.').pop()}` : 'This';
    throw new Error(`${type} files can’t be read here. Use a WAV, MP3, M4A/AAC, OGG, FLAC or AMR recording.`);
  }
  if (buffer.duration > MAX_FILE_SECONDS) throw new Error(TOO_LONG);
  const channels = Array.from({ length: buffer.numberOfChannels }, (_, i) => buffer.getChannelData(i));
  return { samples: resample(mixToMono(channels), buffer.sampleRate), sourceRate: buffer.sampleRate };
}

/** MP4-family file (3GP, M4A, …): starts with an 'ftyp' box. */
function isIsoMedia(bytes) {
  return String.fromCharCode(...bytes.subarray(4, 8)) === 'ftyp';
}

/**
 * Microphone listener: calls onWindow(samples48k, startSeconds) for every
 * 3 seconds of audio. Processing is skipped (not queued) while busy.
 */
export class Listener {
  async start(onWindow) {
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    });
    try {
      this.ctx = new AudioContext({ sampleRate: SAMPLE_RATE });
    } catch {
      this.ctx = new AudioContext(); // some browsers only record at the device rate
    }
    await this.ctx.audioWorklet.addModule(new URL('./mic-worklet.js', import.meta.url));
    const source = this.ctx.createMediaStreamSource(this.stream);
    this.node = new AudioWorkletNode(this.ctx, 'mic-tap');
    const mute = this.ctx.createGain();
    mute.gain.value = 0;
    source.connect(this.node).connect(mute).connect(this.ctx.destination);

    const rate = this.ctx.sampleRate;
    const needed = Math.round(3 * rate);
    let pending = [];
    let pendingLength = 0;
    let elapsed = 0;
    let busy = false;
    this.node.port.onmessage = async ({ data }) => {
      pending.push(data);
      pendingLength += data.length;
      if (pendingLength < needed) return;
      const joined = new Float32Array(pendingLength);
      let offset = 0;
      for (const p of pending) {
        joined.set(p, offset);
        offset += p.length;
      }
      const chunk = joined.subarray(0, needed);
      pending = [joined.slice(needed)];
      pendingLength = pending[0].length;
      const startAt = elapsed;
      elapsed += 3;
      if (busy) return;
      busy = true;
      try {
        await onWindow(resample(chunk, rate), startAt);
      } finally {
        busy = false;
      }
    };
  }

  stop() {
    this.node?.port.close();
    this.stream?.getTracks().forEach((t) => t.stop());
    this.ctx?.close();
    this.node = this.stream = this.ctx = null;
  }
}
