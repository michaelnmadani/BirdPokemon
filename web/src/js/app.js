import { Catalog } from './catalog.js';
import { SightingStore } from './store.js';
import { h, toast } from './ui.js';
import { collectionView } from './views/collection.js';
import { guideView } from './views/guide.js';
import { speciesView } from './views/species.js';
import { groupView, groupsView } from './views/groups.js';
import { captureView } from './views/capture.js';
import { sightingsView, sightingDetailView } from './views/sightings.js';
import { mapView } from './views/map.js';
import { settingsView } from './views/settings.js';

const TABS = [
  { route: 'collection', label: 'Collection', icon: 'grid' },
  { route: 'guide', label: 'Field Guide', icon: 'book' },
  { route: 'capture', label: 'Capture', icon: 'camera' },
  { route: 'sightings', label: 'Sightings', icon: 'list' },
  { route: 'map', label: 'Map', icon: 'map' },
];

const ROUTES = {
  collection: collectionView,
  guide: guideView,
  species: speciesView,
  groups: groupsView,
  group: groupView,
  capture: captureView,
  sightings: sightingsView,
  sighting: sightingDetailView,
  map: mapView,
  settings: settingsView,
};

// Which tab a detail screen belongs to, for highlighting.
const TAB_FOR = { species: 'guide', groups: 'guide', group: 'guide', sighting: 'sightings', settings: 'collection' };

function readPref(key, fallback) {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    return fallback;
  }
}

function writePref(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Private mode etc. — preference just won't persist.
  }
}

class App {
  constructor(catalog, store) {
    this.catalog = catalog;
    this.store = store;
    this.viewStates = new Map();
    this.main = document.getElementById('view');
    this.tabbar = document.getElementById('tabbar');
    const saved = readPref('region', 'AU');
    this.region = catalog.regions.includes(saved) ? saved : (catalog.regions[0] ?? 'AU');
    this.cleanup = null;
  }

  /** Per-screen state that survives navigation (filters, search, capture progress). */
  viewState(key, init) {
    if (!this.viewStates.has(key)) this.viewStates.set(key, init());
    return this.viewStates.get(key);
  }

  setRegion(code) {
    this.region = code;
    writePref('region', code);
  }

  navigate(path) {
    if (location.hash === `#/${path}`) this.render();
    else location.hash = `#/${path}`;
  }

  route() {
    const [name, ...params] = location.hash.replace(/^#\/?/, '').split('/').map(decodeURIComponent);
    return ROUTES[name] ? { name, params } : { name: 'collection', params: [] };
  }

  render() {
    const { name, params } = this.route();
    this.cleanup?.();
    this.cleanup = null;
    const result = ROUTES[name](this, ...params);
    const node = result instanceof Node ? result : result.node;
    this.cleanup = result.cleanup ?? null;
    this.main.replaceChildren(node);
    this.renderTabs(TAB_FOR[name] ?? name);
    const heading = node.querySelector('h1');
    document.title = heading ? `${heading.textContent} · Down Under Bird Collector` : 'Down Under Bird Collector';
    if (!this.keepScroll) window.scrollTo(0, 0);
    this.keepScroll = false;
  }

  renderTabs(active) {
    // Static markup (labels are constants), so a template string is safe here.
    this.tabbar.innerHTML = TABS.map((tab) => {
      const classes = ['tab', tab.route === active ? 'active' : '', tab.route === 'capture' ? 'capture' : ''].join(' ').trim();
      const current = tab.route === active ? ' aria-current="page"' : '';
      return `<a class="${classes}" href="#/${tab.route}"${current}>`
        + `<svg class="icon" aria-hidden="true"><use href="icons/sprite.svg#${tab.icon}"/></svg>`
        + `<span>${tab.label}</span></a>`;
    }).join('');
  }
}

async function boot() {
  const status = document.getElementById('boot-status');
  try {
    const [catalog, store] = await Promise.all([new Catalog().load(), new SightingStore().open()]);
    const app = new App(catalog, store);
    window.addEventListener('hashchange', () => app.render());
    store.addEventListener('change', () => {
      // The capture flow manages its own updates; everything else re-renders.
      if (app.route().name !== 'capture') {
        app.keepScroll = true;
        app.render();
      }
    });
    if (!location.hash) history.replaceState(null, '', '#/collection');
    app.render();
    status?.remove();
    window.dubc = app; // handy for debugging in the console
  } catch (err) {
    console.error(err);
    if (status) status.textContent = `Couldn't start: ${err.message}`;
  }

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').then((reg) => {
      reg.addEventListener('updatefound', () => {
        const worker = reg.installing;
        worker?.addEventListener('statechange', () => {
          if (worker.state === 'installed' && navigator.serviceWorker.controller) {
            toast('An update is ready — reopen the app to use it.');
          }
        });
      });
    }).catch((err) => console.warn('Service worker not registered:', err));
  }

  window.addEventListener('offline', () => toast('You’re offline — everything still works.'));
}

boot();
