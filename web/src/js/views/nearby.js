// Birds spotted within 5 km of where you are: your own sightings (always
// available, even offline) plus recent eBird reports (with an API key).
import { EBirdError, getApiKey, recentNearby } from '../ebird.js';
import { RADIUS_KM, daysAgo, parseEbirdDate, summarizeNearby } from '../nearby.js';
import { formatDate, h, speciesImage } from '../ui.js';
import { baseMap, birdIcon, loadLeaflet } from './map.js';

const SHOW = [
  { id: 'all', label: 'Everything' },
  { id: 'missing', label: 'Not collected yet' },
];

function freshState() {
  return {
    center: null,         // { lat, lon, accuracy }
    locatedAt: 0,
    locStatus: 'idle',    // 'idle' | 'locating' | 'ready' | 'error'
    locMessage: '',
    ebird: { status: 'idle', reports: [], fetchedAt: null, cached: false, message: '' },
    show: 'all',
  };
}

export function nearbyView(app) {
  const state = app.viewState('nearby', freshState);
  const root = h('section.view.nearby');
  const mapHolder = h('div.nearmap', { role: 'region', 'aria-label': 'Map of birds spotted within 5 km' });
  const body = h('div');
  let map = null;
  let layers = null;
  let fittedTo = null;

  const render = () => {
    body.replaceChildren(...content(app, state, render, locate));
    drawMap();
  };

  const drawMap = async () => {
    if (!state.center) return;
    try {
      const L = await loadLeaflet();
      if (!map) {
        map = baseMap(L, mapHolder);
        layers = L.layerGroup().addTo(map);
      }
      layers.clearLayers();
      const here = [state.center.lat, state.center.lon];
      L.circle(here, { radius: RADIUS_KM * 1000, color: '#1f5a46', weight: 2, fillOpacity: 0.06 }).addTo(layers);
      L.circleMarker(here, { radius: 7, color: '#fff', weight: 2, fillColor: '#2f6fd6', fillOpacity: 1 })
        .bindTooltip('You are here').addTo(layers);
      for (const e of entries(app, state)) {
        for (const s of e.mine) {
          L.marker([s.latitude, s.longitude], { icon: birdIcon(L), title: s.speciesCommonName })
            .bindPopup(`<strong>${escapeHtml(s.speciesCommonName)}</strong><br>Your sighting`).addTo(layers);
        }
        if (e.report?.lat != null) {
          L.circleMarker([e.report.lat, e.report.lng], { radius: 5, color: '#c8662b', weight: 1, fillOpacity: 0.8 })
            .bindPopup(`<strong>${escapeHtml(e.name)}</strong><br>${escapeHtml(e.report.locName ?? '')}`).addTo(layers);
        }
      }
      // Only re-fit when the location changes, so panning isn't undone by updates.
      const key = here.join();
      if (fittedTo !== key) {
        // Bounds from the coordinate itself: a circle can't measure itself before the map has a view.
        map.fitBounds(L.latLng(here).toBounds(RADIUS_KM * 2000), { padding: [8, 8] });
        fittedTo = key;
      }
    } catch (err) {
      mapHolder.replaceChildren(h('p.empty', err.message));
    }
  };

  const locate = () => {
    if (!('geolocation' in navigator)) {
      Object.assign(state, { locStatus: 'error', locMessage: 'Location isn’t available in this browser.' });
      render();
      return;
    }
    state.locStatus = 'locating';
    render();
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        state.center = { lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy };
        state.locatedAt = Date.now();
        state.locStatus = 'ready';
        render();
        loadReports();
      },
      (err) => {
        state.locStatus = 'error';
        state.locMessage = err.code === err.PERMISSION_DENIED
          ? 'Location permission is off. Allow it to see birds spotted around you.'
          : 'Couldn’t get a location fix.';
        render();
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 120000 },
    );
  };

  const loadReports = async () => {
    if (!getApiKey()) {
      state.ebird = { ...freshState().ebird, status: 'nokey' };
      render();
      return;
    }
    state.ebird = { ...state.ebird, status: 'loading' };
    render();
    try {
      const result = await recentNearby(state.center, { km: RADIUS_KM });
      state.ebird = { status: 'ready', message: '', ...result };
    } catch (err) {
      state.ebird = { ...freshState().ebird, status: 'error', message: err instanceof EBirdError ? err.message : String(err) };
    }
    render();
  };

  root.append(
    h('header.top', h('h1', 'Nearby'), h('button.btn.small', { type: 'button', onclick: locate }, 'Refresh')),
    h('p.muted.small', `Birds spotted within ${RADIUS_KM} km of where you are.`),
    mapHolder,
    body,
  );

  // Re-locate if we've never located, or the fix is more than two minutes old.
  // Otherwise reuse it, fetching eBird reports if a key was added since or
  // the last results are over ten minutes old.
  if (!state.center || Date.now() - state.locatedAt > 120000) {
    locate();
  } else {
    render();
    const stale = !state.ebird.fetchedAt || Date.now() - state.ebird.fetchedAt > 600000;
    if (getApiKey() ? state.ebird.status !== 'ready' || stale : state.ebird.status !== 'nokey') loadReports();
  }

  return { node: root, cleanup: () => map?.remove() };
}

function entries(app, state) {
  if (!state.center) return [];
  return summarizeNearby({
    mine: app.store.sightings,
    reports: state.ebird.reports,
    center: state.center,
    lookup: (code) => app.catalog.get(code),
  });
}

function content(app, state, render, locate) {
  if (state.locStatus === 'locating' && !state.center) return [h('p.empty', 'Finding your location…')];
  if (state.locStatus === 'error' && !state.center) {
    return [h('div.empty-state', h('p', state.locMessage), h('button.btn.primary', { type: 'button', onclick: locate }, 'Try again'))];
  }
  if (!state.center) return [];

  const all = entries(app, state);
  const missing = all.filter((e) => !app.store.isCollected(e.code));
  const shown = state.show === 'missing' ? missing : all;

  const segmented = h('div.segmented.two', { role: 'tablist' }, SHOW.map((opt) =>
    h('button', {
      type: 'button', role: 'tab', 'aria-selected': String(state.show === opt.id),
      onclick: () => { state.show = opt.id; render(); },
    }, opt.label)));

  return [
    h('div.progress-card',
      h('strong', `${all.length} species spotted within ${RADIUS_KM} km`),
      h('span.muted.small', `${missing.length} you haven’t collected yet`),
    ),
    ebirdNotice(state),
    segmented,
    shown.length
      ? h('ul.rows', shown.map((e) => h('li', nearbyRow(app, e))))
      : h('p.empty', state.show === 'missing' && all.length ? 'You’ve collected everything spotted here. Nice!' : 'Nothing recorded within 5 km yet.'),
  ];
}

function ebirdNotice(state) {
  const e = state.ebird;
  switch (e.status) {
    case 'nokey':
      return h('p.notice', 'Add a free eBird API key in ', h('a', { href: '#/settings' }, 'Settings'),
        ' to also see what other birdwatchers have reported here in the last 30 days.');
    case 'loading':
      return h('p.muted.small', 'Checking eBird for recent reports…');
    case 'error':
      return h('p.notice', e.message);
    case 'ready':
      return h('p.muted.small', `Includes eBird reports from the last 30 days${e.cached ? ` (saved ${formatDate(e.fetchedAt)}, offline)` : ''}.`);
    default:
      return null;
  }
}

function nearbyRow(app, e) {
  const collected = app.store.isCollected(e.code);
  const details = [];
  if (e.mine.length) details.push(`You: ${e.mine.length} sighting${e.mine.length > 1 ? 's' : ''}`);
  if (e.report) {
    const where = e.report.locName ? ` · ${e.report.locName}` : '';
    details.push(`eBird: ${daysAgo(parseEbirdDate(e.report.obsDt))}${where}`);
  }
  const content = [
    h('div.row-img', speciesImage(e.species?.thumbnailURL, e.name, 'thumb'),
      collected ? h('span.seal.small', { 'aria-hidden': 'true' }, '✓') : null),
    h('div.row-text',
      h('strong', e.name),
      h('em.muted.small', e.sciName ?? ''),
      details.map((d) => h('span.meta', d)),
      !e.species ? h('span.meta', 'Not in the field guide yet') : null,
    ),
  ];
  const label = `${e.name}${collected ? ', collected' : ', not collected yet'}`;
  return e.species
    ? h('a.species-row', { href: `#/species/${encodeURIComponent(e.code)}`, 'aria-label': label }, content)
    : h('div.species-row', { 'aria-label': label }, content);
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
