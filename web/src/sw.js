// Service worker: precaches the whole app (and species data) at install so it
// runs with no connection, and keeps species photos once they've been seen.
// The version and precache list below are stamped in by scripts/build.mjs.

const VERSION = '__VERSION__';
const APP_CACHE = `app-${VERSION}`;
const PHOTO_CACHE = 'species-photos';
const BIRDNET_CACHE = 'birdnet-v2.4'; // same name as js/soundid.js
const PRECACHE = __PRECACHE__;
const PHOTO_HOSTS = ['inaturalist-open-data.s3.amazonaws.com', 'static.inaturalist.org'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(APP_CACHE).then((cache) => cache.addAll(PRECACHE)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('app-') && key !== APP_CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin === self.location.origin && /\/(models\/birdnet|vendor\/litert)\//.test(url.pathname)) {
    event.respondWith(onDemand(request));
  } else if (url.origin === self.location.origin) {
    event.respondWith(appShell(request));
  } else if (PHOTO_HOSTS.includes(url.hostname) && request.destination === 'image') {
    // Only photos: audio uses range requests that a cached full response would break.
    event.respondWith(speciesPhoto(request));
  }
  // Everything else (bird calls, map tiles, eBird) goes straight to the network.
});

async function appShell(request) {
  const cache = await caches.open(APP_CACHE);
  const cached = await cache.match(request, { ignoreSearch: true });
  if (cached) return cached;
  try {
    return await fetch(request);
  } catch (err) {
    if (request.mode === 'navigate') {
      const shell = await cache.match('./index.html');
      if (shell) return shell;
    }
    throw err;
  }
}

// Sound ID runtime and model: cached the first time they're used.
async function onDemand(request) {
  const cache = await caches.open(BIRDNET_CACHE);
  const cached = await cache.match(request.url);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok && request.method === 'GET') cache.put(request.url, response.clone());
  return response;
}

async function speciesPhoto(request) {
  const cache = await caches.open(PHOTO_CACHE);
  const cached = await cache.match(request.url);
  if (cached) return cached;
  const response = await fetch(request.url, { mode: 'cors' });
  if (response.ok) cache.put(request.url, response.clone());
  return response;
}
