import { COLORS, REGIONS, photoCredit, sizeInfo } from '../model.js';
import { backButton, colorDot, h, speciesImage } from '../ui.js';
import { sightingRow } from './sightings.js';

function groupsBlock(app, code) {
  const groups = app.catalog.groupsFor(app.region).byCode.get(code) ?? [];
  if (!groups.length) return null;
  return h('p.group-links', h('span.muted.small', 'Groups '), groups.map((g) =>
    h('a.pill', { href: `#/group/${encodeURIComponent(g.id)}` }, g.kind === 'genus' ? `${g.name} (${g.genus})` : `${g.emoji} ${g.name}`)));
}

export function speciesView(app, code) {
  const species = app.catalog.get(code);
  if (!species) {
    return h('section.view', h('header.top', h('a.back', { href: '#/guide' }, '‹ Field Guide')), h('p.empty', 'Species not found.'));
  }
  const collected = app.store.isCollected(code);
  const mine = app.store.ofSpecies(code);
  const size = sizeInfo(species.sizeCategory);
  const credit = photoCredit(species);

  return h('section.view.detail',
    h('header.top', backButton(app, 'guide')),
    speciesImage(species.thumbnailURL, species.commonName, 'hero'),
    credit ? h('p.credit', `Photo: ${credit} via iNaturalist`) : null,
    h('h1', species.commonName),
    h('p.sci', species.scientificName),
    h('div.pills',
      collected ? h('span.pill.accent', '✓ Collected') : h('span.pill', 'Not collected yet'),
      h('span.pill', `${size.label} · ${size.length}`),
    ),
    species.primaryColors.length
      ? h('p.colors', h('span.muted.small', 'Colours '), species.primaryColors.map((c) => colorDot(COLORS[c], c, 16)))
      : null,
    groupsBlock(app, code),
    h('h2', 'Taxonomy'),
    h('dl.facts',
      h('dt', 'Family'), h('dd', species.familyDisplayName),
      h('dt', 'Order'), h('dd', species.order),
      h('dt', 'Regions'), h('dd', species.regionCodes.map((r) => REGIONS[r]?.flag ?? r).join(' ')),
    ),
    h('h2', 'Your sightings'),
    mine.length
      ? h('ul.rows', mine.map((s) => h('li', sightingRow(app, s))))
      : h('p.muted', 'You haven’t collected one yet — go find it!'),
    h('p.links',
      h('a', { href: species.ebirdURL, target: '_blank', rel: 'noopener' }, 'Read more on eBird ↗'),
      species.wikipediaURL ? h('a', { href: species.wikipediaURL, target: '_blank', rel: 'noopener' }, 'Wikipedia ↗') : null,
    ),
  );
}
