import { COLORS, emptyCriteria, matches, sizeInfo } from '../model.js';
import { colorDot, h, speciesImage } from '../ui.js';
import { filterBar } from './filters.js';

export function guideView(app) {
  const state = app.viewState('guide', () => ({ criteria: emptyCriteria() }));
  const species = app.catalog.species(app.region);
  const list = h('ul.rows');
  const empty = h('p.empty');
  const bar = filterBar(state.criteria, species, renderList);

  function renderList() {
    const results = species.filter((s) => matches(state.criteria, s));
    bar.update(results.length);
    list.replaceChildren(...results.map((s) =>
      h('li', speciesRow(s, app.store.isCollected(s.ebirdCode), `#/species/${encodeURIComponent(s.ebirdCode)}`))));
    empty.textContent = results.length ? '' : 'No matches. Try a shorter name or remove a filter.';
  }
  renderList();

  return h('section.view', h('header.top', h('h1', 'Field Guide')), bar.node, list, empty);
}

/** One species row; `href` makes it a link, `onclick` a button. */
export function speciesRow(species, collected, href, onclick) {
  const content = [
    h('div.row-img', speciesImage(species.thumbnailURL, species.commonName, 'thumb'),
      collected ? h('span.seal.small', { 'aria-hidden': 'true' }, '✓') : null),
    h('div.row-text',
      h('strong', species.commonName),
      h('em.muted.small', species.scientificName),
      h('span.meta',
        h('span', species.familyDisplayName), ' · ', h('span', sizeInfo(species.sizeCategory).label), ' ',
        species.primaryColors.slice(0, 3).map((c) => colorDot(COLORS[c], c))),
    ),
  ];
  const label = `${species.commonName}${collected ? ', collected' : ''}`;
  return href
    ? h('a.species-row', { href, 'aria-label': label }, content)
    : h('button.species-row', { type: 'button', onclick, 'aria-label': label }, content);
}
