// Downscale a picked/taken photo to the same sizes the iOS app stores.

export const FULL_MAX = 2048;
export const THUMB_MAX = 400;

async function decode(file) {
  if ('createImageBitmap' in window) {
    try {
      return await createImageBitmap(file, { imageOrientation: 'from-image' });
    } catch {
      // Fall through to <img> decoding (older Safari, unusual formats).
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    return img;
  } finally {
    URL.revokeObjectURL(url);
  }
}

function toJpeg(source, maxDimension, quality) {
  const width = source.width ?? source.naturalWidth;
  const height = source.height ?? source.naturalHeight;
  const scale = Math.min(1, maxDimension / Math.max(width, height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('Could not encode photo'))), 'image/jpeg', quality);
  });
}

/** -> { full: Blob, thumb: Blob } */
export async function processPhoto(file) {
  const source = await decode(file);
  const [full, thumb] = await Promise.all([toJpeg(source, FULL_MAX, 0.85), toJpeg(source, THUMB_MAX, 0.8)]);
  source.close?.();
  return { full, thumb };
}
