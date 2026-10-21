// Browse species by group: curated bird groups and genera.
import { backButton, h, speciesImage } from '../ui.js';
import { speciesRow } from './guide.js';

function progress(app, group) {
  const have = group.species.filter((s) => app.store.isCollected(s.ebirdCode)).length;
  return { have, total: group.species.length };
}

/** A tappable group card/row. */
export function groupLink(app, group, compact = false) {
  const { have, total } = progress(app, group);
  const href = `#/group/${encodeURIComponent(group.id)}`;
  if (compact) {
    return h('a.group-chip', { href }, h('span', { 'aria-hidden': 'true' }, group.emoji), ` ${group.name} `, h('span.muted.small', String(total)));
  }
  const cover = group.species.find((s) => s.thumbnailURL);
  return h('a.species-row.group-row', { href, 'aria-label': `${group.name}, ${have} of ${total} collected` },
    h('div.row-img', speciesImage(cover?.thumbnailURL, group.name, 'thumb')),
    h('div.row-text',
      h('strong', group.kind === 'genus' ? group.name : `${group.emoji} ${group.name}`),
      group.kind === 'genus' ? h('em.muted.small', `Genus ${group.genus}`) : h('span.muted.small', 'Bird group'),
      h('span.meta', `${have} of ${total} collected`),
    ),
  );
}

export function groupsView(app) {
  const state = app.viewState('groups', () => ({ search: '' }));
  const { groups } = app.catalog.groupsFor(app.region);
  const list = h('div');

  const render = () => {
    const needle = state.search.trim().toLowerCase();
    const match = (g) => !needle || `${g.name} ${g.genus ?? ''} ${g.species.map((s) => s.commonName).join(' ')}`.toLowerCase().includes(needle);
    const birdGroups = groups.filter((g) => g.kind === 'group' && match(g));
    const genera = groups.filter((g) => g.kind === 'genus' && match(g));
    list.replaceChildren(
      birdGroups.length ? h('h2', 'Bird groups') : null,
      h('ul.rows', birdGroups.map((g) => h('li', groupLink(app, g)))),
      genera.length ? h('h2', 'Genera') : null,
      genera.length ? h('p.muted.small', 'Closely related species that share a genus.') : null,
      h('ul.rows', genera.map((g) => h('li', groupLink(app, g)))),
      !birdGroups.length && !genera.length ? h('p.empty', 'No groups match.') : null,
    );
  };

  const search = h('input.search', {
    type: 'search', placeholder: 'Search groups, e.g. parrots or rosellas', value: state.search,
    'aria-label': 'Search groups', autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false',
  });
  search.addEventListener('input', () => { state.search = search.value; render(); });
  render();

  return h('section.view', h('header.top', backButton(app, 'guide'), h('h1', 'Groups')), search, list);
}

export function groupView(app, id) {
  const group = app.catalog.group(app.region, id);
  if (!group) {
    return h('section.view', h('header.top', backButton(app, 'groups')), h('p.empty', 'Group not found.'));
  }
  const { have, total } = progress(app, group);
  const parents = group.kind === 'genus'
    ? [...new Set(group.species.flatMap((s) => (app.catalog.groupsFor(app.region).byCode.get(s.ebirdCode) ?? []).filter((g) => g.kind === 'group')))]
    : [];

  return h('section.view',
    h('header.top', backButton(app, 'groups'), h('h1', group.kind === 'genus' ? group.name : `${group.emoji} ${group.name}`)),
    group.kind === 'genus' ? h('p.sci', `Genus ${group.genus}`) : null,
    parents.length ? h('p.muted.small', 'Part of ', parents.map((g, i) => [i ? ', ' : '', h('a', { href: `#/group/${encodeURIComponent(g.id)}` }, g.name)])) : null,
    h('div.progress-card',
      h('strong', `${have} of ${total} collected`),
      h('progress', { max: Math.max(total, 1), value: have }),
    ),
    h('ul.rows', group.species.map((s) =>
      h('li', speciesRow(s, app.store.isCollected(s.ebirdCode), `#/species/${encodeURIComponent(s.ebirdCode)}`)))),
  );
}
