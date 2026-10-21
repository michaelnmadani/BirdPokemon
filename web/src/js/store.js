// Sightings and their photos, kept in IndexedDB so everything works offline.
// Record shape matches the iOS `Sighting` model.

const DB_NAME = 'down-under-bird-collector';
const DB_VERSION = 1;

function request(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function done(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error ?? new Error('Transaction aborted'));
  });
}

export class SightingStore extends EventTarget {
  constructor() {
    super();
    this.db = null;
    this.sightings = [];
    this.collected = new Set();
    this.latest = new Map();
    this.urls = new Map(); // `${id}:${kind}` -> object URL
  }

  async open() {
    const open = indexedDB.open(DB_NAME, DB_VERSION);
    open.onupgradeneeded = () => {
      const db = open.result;
      if (!db.objectStoreNames.contains('sightings')) db.createObjectStore('sightings', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('photos')) db.createObjectStore('photos', { keyPath: 'id' });
    };
    this.db = await request(open);
    const tx = this.db.transaction('sightings');
    this.#set(await request(tx.objectStore('sightings').getAll()));
    // Ask the browser not to evict our data under storage pressure.
    navigator.storage?.persist?.().catch(() => {});
    return this;
  }

  #set(list) {
    this.sightings = list.sort((a, b) => (a.capturedAt < b.capturedAt ? 1 : -1));
    this.collected = new Set(list.map((s) => s.speciesCode));
    this.latest = new Map();
    for (const s of this.sightings) if (!this.latest.has(s.speciesCode)) this.latest.set(s.speciesCode, s);
    this.dispatchEvent(new Event('change'));
  }

  isCollected(code) {
    return this.collected.has(code);
  }

  ofSpecies(code) {
    return this.sightings.filter((s) => s.speciesCode === code);
  }

  get(id) {
    return this.sightings.find((s) => s.id === id) ?? null;
  }

  /** draft: { species, photo: {full, thumb} | null, capturedAt: Date, coordinate, accuracy, locationSource, notes } */
  async add(draft) {
    const id = crypto.randomUUID();
    const sighting = {
      id,
      userId: 'local',
      speciesCode: draft.species.ebirdCode,
      speciesCommonName: draft.species.commonName,
      speciesSciName: draft.species.scientificName,
      capturedAt: draft.capturedAt.toISOString(),
      createdAt: new Date().toISOString(),
      latitude: draft.coordinate?.lat ?? null,
      longitude: draft.coordinate?.lon ?? null,
      locationAccuracy: draft.accuracy ?? null,
      locationSource: draft.coordinate ? draft.locationSource : null,
      notes: draft.notes || null,
      mlTopPrediction: draft.mlTop?.code ?? null,
      mlTopConfidence: draft.mlTop?.confidence ?? null,
      identifiedBy: draft.identifiedBy ?? null,
      userOverrode: false,
      hasPhoto: Boolean(draft.photo),
    };
    const tx = this.db.transaction(['sightings', 'photos'], 'readwrite');
    tx.objectStore('sightings').put(sighting);
    if (draft.photo) tx.objectStore('photos').put({ id, full: draft.photo.full, thumb: draft.photo.thumb });
    await done(tx);
    this.#set([...this.sightings, sighting]);
    return sighting;
  }

  async delete(ids) {
    const tx = this.db.transaction(['sightings', 'photos'], 'readwrite');
    for (const id of ids) {
      tx.objectStore('sightings').delete(id);
      tx.objectStore('photos').delete(id);
    }
    await done(tx);
    for (const id of ids) this.#revoke(id);
    this.#set(this.sightings.filter((s) => !ids.includes(s.id)));
  }

  async deleteAll() {
    await this.delete(this.sightings.map((s) => s.id));
  }

  /** Object URL for a sighting's photo ('full' or 'thumb'), or null. */
  async photoURL(id, kind = 'thumb') {
    const key = `${id}:${kind}`;
    if (this.urls.has(key)) return this.urls.get(key);
    const record = await request(this.db.transaction('photos').objectStore('photos').get(id));
    const blob = record?.[kind] ?? record?.full;
    if (!blob) return null;
    const url = URL.createObjectURL(blob);
    this.urls.set(key, url);
    return url;
  }

  #revoke(id) {
    for (const kind of ['thumb', 'full']) {
      const key = `${id}:${kind}`;
      if (this.urls.has(key)) {
        URL.revokeObjectURL(this.urls.get(key));
        this.urls.delete(key);
      }
    }
  }
}
