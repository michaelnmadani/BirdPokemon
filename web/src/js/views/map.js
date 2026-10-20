// Map of sightings using a vendored copy of Leaflet (cached for offline use).
// Map tiles come from OpenStreetMap and need a connection; pins always show.
import { formatDate, h } from '../ui.js';

let leafletPromise;
function loadLeaflet() {
  leafletPromise ??= new Promise((resolve, reject) => {
    if (window.L) return resolve(window.L);
    const script = document.createElement('script');
    script.src = 'vendor/leaflet/leaflet.js';
    script.onload = () => resolve(window.L);
    script.onerror = () => reject(new Error('Map library failed to load'));
    document.head.append(script);
  });
  return leafletPromise;
}

const AUSTRALIA = [[-43.8, 112.9], [-10.5, 153.8]];

function baseMap(L, el) {
  const map = L.map(el, { zoomControl: true, attributionControl: true });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
  return map;
}

function birdIcon(L) {
  return L.divIcon({ className: 'pin', html: '<span>🐦</span>', iconSize: [32, 32], iconAnchor: [16, 30], popupAnchor: [0, -26] });
}

export async function smallMap(el, sighting) {
  const L = await loadLeaflet();
  const map = baseMap(L, el);
  const point = [sighting.latitude, sighting.longitude];
  L.marker(point, { icon: birdIcon(L) }).addTo(map);
  map.setView(point, 14);
  return map;
}

export function mapView(app) {
  const located = app.store.sightings.filter((s) => s.latitude != null && s.longitude != null);
  const holder = h('div.bigmap', { role: 'region', 'aria-label': 'Map of your sightings' });
  const note = h('p.mapnote', located.length
    ? (navigator.onLine ? '' : 'Offline: map tiles need internet, but your pins still show.')
    : app.store.sightings.length ? 'None of your sightings have a location yet.' : 'Your sightings will appear here.');

  let map = null;
  requestAnimationFrame(async () => {
    try {
      const L = await loadLeaflet();
      map = baseMap(L, holder);
      const icon = birdIcon(L);
      const bounds = [];
      for (const s of located) {
        const point = [s.latitude, s.longitude];
        bounds.push(point);
        const popup = h('div',
          h('strong', s.speciesCommonName), h('br'),
          h('span', formatDate(s.capturedAt)), h('br'),
          h('a', { href: `#/sighting/${encodeURIComponent(s.id)}` }, 'View sighting ›'));
        L.marker(point, { icon, title: s.speciesCommonName }).bindPopup(popup).addTo(map);
      }
      if (bounds.length) map.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 });
      else map.fitBounds(AUSTRALIA);
    } catch (err) {
      holder.replaceChildren(h('p.empty', err.message));
    }
  });

  return {
    node: h('section.view.mapview', h('header.top', h('h1', 'Map'), h('span.muted.small', `${located.length} pinned`)), holder, note),
    cleanup: () => map?.remove(),
  };
}
