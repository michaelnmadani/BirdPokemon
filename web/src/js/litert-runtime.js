// LiteRT.js (TensorFlow Lite in WASM), loaded once and shared by sound and
// photo identification. Downloaded on first use and kept by the service worker.
const WASM_DIR = new URL('../vendor/litert/', import.meta.url).href;

let runtime = null;

/** -> the LiteRT module ({ loadAndCompile, Tensor, … }), initialised. */
export function liteRt() {
  runtime ??= (async () => {
    const lib = await import('../vendor/litert/litert.js');
    await lib.loadLiteRt(WASM_DIR);
    return lib;
  })().catch((err) => {
    runtime = null;
    throw err;
  });
  return runtime;
}
