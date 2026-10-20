// Recent eBird reports near a point. Needs a free personal API key
// (https://ebird.org/api/keygen) entered in Settings; it stays in this browser.
// The last result is cached so the Nearby screen still has something offline.

const KEY_STORAGE = 'ebirdApiKey';
const CACHE_STORAGE = 'ebirdNearbyCache';

function storage() {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export function getApiKey() {
  return storage()?.getItem(KEY_STORAGE) ?? '';
}

export function setApiKey(key) {
  const s = storage();
  if (!s) return;
  if (key) s.setItem(KEY_STORAGE, key.trim());
  else s.removeItem(KEY_STORAGE);
}

export class EBirdError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

/** -> { reports, fetchedAt: Date, cached: boolean } */
export async function recentNearby(center, { km = 5, days = 30 } = {}) {
  const key = getApiKey();
  if (!key) throw new EBirdError('No eBird API key', 0);
  const url = new URL('https://api.ebird.org/v2/data/obs/geo/recent');
  // Rounded to ~1 km: plenty for a 5 km search, and less precise than your actual spot.
  url.searchParams.set('lat', center.lat.toFixed(2));
  url.searchParams.set('lng', center.lon.toFixed(2));
  // +1 km covers the rounding; the app then keeps only reports within `km` of you.
  url.searchParams.set('dist', String(km + 1));
  url.searchParams.set('back', String(days));
  url.searchParams.set('key', key); // query param avoids a CORS preflight
  try {
    const resp = await fetch(url);
    if (resp.status === 401 || resp.status === 403) throw new EBirdError('eBird rejected the API key — check it in Settings.', resp.status);
    if (!resp.ok) throw new EBirdError(`eBird returned ${resp.status}`, resp.status);
    const reports = await resp.json();
    const fetchedAt = new Date();
    storage()?.setItem(CACHE_STORAGE, JSON.stringify({ center, reports, fetchedAt: fetchedAt.toISOString() }));
    return { reports, fetchedAt, cached: false };
  } catch (err) {
    const cached = cachedNear(center);
    if (cached) return cached;
    throw err instanceof EBirdError ? err : new EBirdError('Couldn’t reach eBird — you may be offline.', -1);
  }
}

function cachedNear(center) {
  try {
    const raw = JSON.parse(storage()?.getItem(CACHE_STORAGE) ?? 'null');
    if (!raw) return null;
    // Only reuse it if it was fetched for (roughly) the same place.
    const dLat = Math.abs(raw.center.lat - center.lat);
    const dLon = Math.abs(raw.center.lon - center.lon);
    if (dLat > 0.02 || dLon > 0.02) return null;
    return { reports: raw.reports, fetchedAt: new Date(raw.fetchedAt), cached: true };
  } catch {
    return null;
  }
}
