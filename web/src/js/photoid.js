// Photo identification in the browser: MobileNet V2 trained on iNaturalist
// bird photos (Google, Apache-2.0), run with LiteRT.js. Only suggests species
// in the field guide (see photoid-core.js); the user always confirms.
import { liteRt } from './litert-runtime.js';
import { INPUT_SIZE, centreSquare, dequantize, mapLabels, parseLabels, suggestions } from './photoid-core.js';

const MODEL_URL = new URL('../models/photo/BirdPhotoClassifier.tflite', import.meta.url).href;
const LABELS_URL = new URL('../models/photo/BirdPhotoClassifier_labels.txt', import.meta.url).href;

let loading = null;

async function fetchBytes(url) {
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`download failed (${resp.status})`);
  return new Uint8Array(await resp.arrayBuffer());
}

function load(catalogSpecies) {
  loading ??= (async () => {
    const { loadAndCompile, Tensor } = await liteRt();
    const [modelBytes, labelBytes] = await Promise.all([fetchBytes(MODEL_URL), fetchBytes(LABELS_URL)]);
    const model = await loadAndCompile(modelBytes, { accelerator: 'wasm' });
    const labels = parseLabels(new TextDecoder().decode(labelBytes));
    return { model, Tensor, codes: mapLabels(labels, catalogSpecies) };
  })().catch((err) => {
    loading = null;
    throw err;
  });
  return loading;
}

/** The photo's centre square at 224 × 224, as RGB bytes. */
async function pixels(file) {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
  const { sx, sy, size } = centreSquare(bitmap.width, bitmap.height);
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = INPUT_SIZE;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(bitmap, sx, sy, size, size, 0, 0, INPUT_SIZE, INPUT_SIZE);
  bitmap.close?.();
  const rgba = ctx.getImageData(0, 0, INPUT_SIZE, INPUT_SIZE).data;
  const rgb = new Uint8Array(INPUT_SIZE * INPUT_SIZE * 3);
  for (let i = 0, j = 0; i < rgba.length; i += 4) {
    rgb[j++] = rgba[i];
    rgb[j++] = rgba[i + 1];
    rgb[j++] = rgba[i + 2];
  }
  return rgb;
}

/** -> { suggestions: [{ code, confidence }], unsure } for a photo file. */
export async function identifyPhoto(file, catalogSpecies) {
  const { model, Tensor, codes } = await load(catalogSpecies);
  const input = new Tensor(await pixels(file), [1, INPUT_SIZE, INPUT_SIZE, 3]);
  try {
    const results = await model.run(input);
    const output = await results[0].moveTo('wasm');
    const bytes = Uint8Array.from(output.toTypedArray());
    output.delete();
    return suggestions(dequantize(bytes), codes);
  } finally {
    input.delete();
  }
}
