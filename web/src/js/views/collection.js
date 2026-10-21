import { REGIONS, emptyCriteria, matches } from '../model.js';
import { GRID_SIZES, GROUPINGS, sections } from '../sections.js';
import { h, sightingPicture, speciesImage } from '../ui.js';
import { filterBar } from './filters.js';

const SHOW = [
  { id: 'all', label: 'All' },
  { id: 'collected', label: 'Collected' },
  { id: 'missing', label: 'To find' },
];

// Grouping and card size are remembered in this browser.
function readPref(key, allowed, fallback) {
  try {
    const value = localStorage.getItem(key);
    return allowed.some((o) => o.id === value) ? value : fallback;
  } catch {
    return fallback;
  }
}

function writePref(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Private mode etc. — just won't persist.
  }
}

export function collectionView(app) {
  const state = app.viewState('collection', () => ({
    criteria: emptyCriteria(),
    show: 'all',
    groupBy: readPref('collection.groupBy', GROUPINGS, 'none'),
    gridSize: readPref('collection.gridSize', GRID_SIZES, 'medium'),
  }));
  const { store } = app;
  const species = app.catalog.species(app.region);
  const have = species.filter((s) => store.isCollected(s.ebirdCode)).length;
  const region = REGIONS[app.region] ?? { name: app.region, flag: '' };

  const results = h('div.results');
  const empty = h('p.empty');
  const bar = filterBar(state.criteria, species, renderGrid, 'Search your collection');

  const segmented = h('div.segmented', { role: 'tablist' }, SHOW.map((opt) =>
    h('button', {
      type: 'button', role: 'tab', 'aria-selected': String(state.show === opt.id),
      onclick: () => {
        state.show = opt.id;
        segmented.querySelectorAll('button').forEach((b, i) => b.setAttribute('aria-selected', String(SHOW[i].id === opt.id)));
        renderGrid();
      },
    }, opt.label)));

  const groupSelect = h('select', { 'aria-label': 'Group by' },
    GROUPINGS.map((g) => h('option', { value: g.id, selected: g.id === state.groupBy }, g.label)));
  groupSelect.addEventListener('change', () => {
    state.groupBy = groupSelect.value;
    writePref('collection.groupBy', state.groupBy);
    renderGrid();
  });

  const sizePicker = h('div.size-picker', { role: 'radiogroup', 'aria-label': 'Picture size' }, GRID_SIZES.map((z) =>
    h('button', {
      type: 'button', role: 'radio', 'aria-checked': String(state.gridSize === z.id), 'aria-label': `${z.id} pictures`,
      onclick: () => {
        state.gridSize = z.id;
        writePref('collection.gridSize', z.id);
        sizePicker.querySelectorAll('button').forEach((b, i) => b.setAttribute('aria-checked', String(GRID_SIZES[i].id === z.id)));
        applySize();
      },
    }, z.label)));

  function applySize() {
    const size = GRID_SIZES.find((z) => z.id === state.gridSize) ?? GRID_SIZES[1];
    results.style.setProperty('--card-min', `${size.min}px`);
    results.dataset.size = size.id;
  }
  applySize();

  function renderGrid() {
    const entries = species.filter((s) => {
      if (!matches(state.criteria, s)) return false;
      const collected = store.isCollected(s.ebirdCode);
      return state.show === 'all' || (state.show === 'collected' ? collected : !collected);
    });
    bar.update(entries.length);
    const groups = state.groupBy === 'group' ? app.catalog.groupsFor(app.region).groups : [];
    results.replaceChildren(...(entries.length ? sections(entries, state.groupBy, groups) : []).map((section) => [
      section.title ? sectionHeader(section, store) : null,
      h('div.grid', section.species.map((s) => card(app, s))),
    ]).flat().filter(Boolean));
    empty.textContent = entries.length ? '' : (state.show === 'collected'
      ? 'Nothing collected yet — head to Capture and photograph your first bird.'
      : 'No species match. Try clearing filters.');
  }
  renderGrid();

  return h('section.view',
    h('header.top',
      h('h1', 'Collection'),
      h('a.iconbtn', { href: '#/settings', 'aria-label': 'Settings' }, '⚙︎'),
    ),
    h('div.progress-card',
      h('strong', `${region.flag} ${have} of ${species.length} collected`),
      h('progress', { max: Math.max(species.length, 1), value: have }),
    ),
    segmented,
    bar.node,
    h('div.row.grid-options',
      h('label.group-by', h('span.muted.small', 'Group by'), groupSelect),
      h('span.spacer'),
      sizePicker),
    results,
    empty,
  );
}

function sectionHeader(section, store) {
  const have = section.species.filter((s) => store.isCollected(s.ebirdCode)).length;
  return h('h2.section-head',
    section.emoji ? h('span', { 'aria-hidden': 'true' }, section.emoji) : null,
    section.swatch ? h('span.swatch', { style: { background: section.swatch }, 'aria-hidden': 'true' }) : null,
    h('span.section-title', section.title),
    h('span.muted.small', `${have} / ${section.species.length}`));
}

function card(app, species) {
  const collected = app.store.isCollected(species.ebirdCode);
  const latest = app.store.latest.get(species.ebirdCode);
  const image = collected && latest
    ? sightingPicture(app, latest, 'thumb', 'card-img')
    : speciesImage(species.thumbnailURL, species.commonName, 'card-img');
  return h(`a.card${collected ? '.collected' : '.hidden'}`, {
    href: `#/species/${encodeURIComponent(species.ebirdCode)}`,
    'aria-label': `${species.commonName}, ${collected ? 'collected' : 'not collected yet'}`,
  },
  image,
  collected ? h('span.seal', { 'aria-hidden': 'true' }, '✓') : h('span.mystery', { 'aria-hidden': 'true' }, '?'),
  h('span.name', species.commonName));
}
