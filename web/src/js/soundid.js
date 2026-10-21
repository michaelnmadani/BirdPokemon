// BirdNET V2.4 sound identification in the browser, via LiteRT.js (WASM).
// The model (~52 MB) downloads on first use and is kept in Cache Storage,
// so after that it works offline. Model: CC BY-NC-SA 4.0, Cornell Lab of
// Ornithology & Chemnitz University of Technology.
import { SAMPLE_RATE, WINDOW, mapLabels, mixToMono, parseLabels, resample } from './soundid-core.js';

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

/** Decode an audio file to 48 kHz mono. */
export async function decodeFile(file) {
  const ctx = new OfflineAudioContext(1, 1, SAMPLE_RATE);
  const buffer = await ctx.decodeAudioData(await file.arrayBuffer());
  if (buffer.duration > MAX_FILE_SECONDS) throw new Error('Recordings longer than 10 minutes aren’t supported.');
  const channels = Array.from({ length: buffer.numberOfChannels }, (_, i) => buffer.getChannelData(i));
  return resample(mixToMono(channels), buffer.sampleRate);
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
