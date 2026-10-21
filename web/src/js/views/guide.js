import { COLORS, emptyCriteria, matches, sizeInfo } from '../model.js';
import { colorDot, h, speciesImage } from '../ui.js';
import { groupsMatching } from '../groups.js';
import { filterBar } from './filters.js';
import { groupLink } from './groups.js';

export function guideView(app) {
  const state = app.viewState('guide', () => ({ criteria: emptyCriteria() }));
  const species = app.catalog.species(app.region);
  const { groups } = app.catalog.groupsFor(app.region);
  const list = h('ul.rows');
  const empty = h('p.empty');
  const matchingGroups = h('div');
  const bar = filterBar(state.criteria, species, renderList);

  // Bird groups as a scrollable row of chips, plus a link to every group and genus.
  const chips = h('div.group-chips', { role: 'list', 'aria-label': 'Bird groups' },
    groups.filter((g) => g.kind === 'group').map((g) => groupLink(app, g, true)),
    h('a.group-chip.more', { href: '#/groups' }, 'All groups & genera ›'));

  function renderList() {
    const found = groupsMatching(groups, state.criteria.search);
    matchingGroups.replaceChildren(...(found.length
      ? [h('h3', 'Groups'), h('ul.rows', found.map((g) => h('li', groupLink(app, g)))), h('h3', 'Species')]
      : []));
    const results = species.filter((s) => matches(state.criteria, s));
    bar.update(results.length);
    list.replaceChildren(...results.map((s) =>
      h('li', speciesRow(s, app.store.isCollected(s.ebirdCode), `#/species/${encodeURIComponent(s.ebirdCode)}`))));
    empty.textContent = results.length ? '' : 'No matches. Try a shorter name or remove a filter.';
  }
  renderList();

  return h('section.view', h('header.top', h('h1', 'Field Guide')), bar.node, chips, matchingGroups, list, empty);
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
