// "Spotted near here": your own sightings plus recent eBird reports within a
// radius of a point. Pure helpers so they run under node --test.

export const RADIUS_KM = 5;

/** Great-circle distance in km. */
export function distanceKm(a, b) {
  const R = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function sightingsWithin(sightings, center, km = RADIUS_KM) {
  return sightings.filter((s) => s.latitude != null && s.longitude != null
    && distanceKm(center, { lat: s.latitude, lon: s.longitude }) <= km);
}

/**
 * Merge your nearby sightings and eBird observations into one entry per
 * species, most recently seen first.
 * -> [{ code, name, sciName, species|null, mine: sighting[], report: obs|null, lastSeen: Date }]
 */
export function summarizeNearby({ mine, reports, center, km = RADIUS_KM, lookup }) {
  const entries = new Map();
  const entry = (code, name, sciName) => {
    if (!entries.has(code)) {
      entries.set(code, { code, name, sciName, species: lookup(code), mine: [], report: null, lastSeen: new Date(0) });
    }
    return entries.get(code);
  };
  for (const s of sightingsWithin(mine, center, km)) {
    const e = entry(s.speciesCode, s.speciesCommonName, s.speciesSciName);
    e.mine.push(s);
    const at = new Date(s.capturedAt);
    if (at > e.lastSeen) e.lastSeen = at;
  }
  for (const r of reports ?? []) {
    if (r.lat != null && r.lng != null && distanceKm(center, { lat: r.lat, lon: r.lng }) > km) continue;
    const e = entry(r.speciesCode, r.comName, r.sciName);
    const at = parseEbirdDate(r.obsDt);
    if (!e.report || at > parseEbirdDate(e.report.obsDt)) e.report = r;
    if (at > e.lastSeen) e.lastSeen = at;
  }
  return [...entries.values()].sort((a, b) => b.lastSeen - a.lastSeen || a.name.localeCompare(b.name));
}

/** eBird "2025-09-14 07:30" (local time at the site) -> Date. */
export function parseEbirdDate(value) {
  const m = value?.match(/^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?/);
  if (!m) return new Date(0);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4] ?? 0), Number(m[5] ?? 0));
}

/** "today", "yesterday", "3 days ago". */
export function daysAgo(date, now = new Date()) {
  const start = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const days = Math.round((start(now) - start(date)) / 86400000);
  if (days <= 0) return 'today';
  if (days === 1) return 'yesterday';
  return `${days} days ago`;
}
