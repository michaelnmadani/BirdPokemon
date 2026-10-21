import { REGIONS, emptyCriteria, matches } from '../model.js';
import { h, sightingPicture, speciesImage } from '../ui.js';
import { filterBar } from './filters.js';

const SHOW = [
  { id: 'all', label: 'All' },
  { id: 'collected', label: 'Collected' },
  { id: 'missing', label: 'To find' },
];

export function collectionView(app) {
  const state = app.viewState('collection', () => ({ criteria: emptyCriteria(), show: 'all' }));
  const { store } = app;
  const species = app.catalog.species(app.region);
  const have = species.filter((s) => store.isCollected(s.ebirdCode)).length;
  const region = REGIONS[app.region] ?? { name: app.region, flag: '' };

  const grid = h('div.grid');
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

  function renderGrid() {
    const entries = species.filter((s) => {
      if (!matches(state.criteria, s)) return false;
      const collected = store.isCollected(s.ebirdCode);
      return state.show === 'all' || (state.show === 'collected' ? collected : !collected);
    });
    bar.update(entries.length);
    grid.replaceChildren(...entries.map((s) => card(app, s)));
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
    grid,
    empty,
  );
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
