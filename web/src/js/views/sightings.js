import { backButton, confirmDialog, formatCoord, formatDate, h, sightingPicture } from '../ui.js';
import { smallMap } from './map.js';

export function sightingRow(app, s) {
  return h('a.species-row', { href: `#/sighting/${encodeURIComponent(s.id)}` },
    h('div.row-img', sightingPicture(app, s, 'thumb', 'thumb')),
    h('div.row-text',
      h('strong', s.speciesCommonName),
      h('span.muted.small', formatDate(s.capturedAt)),
      h('span.muted.small', s.latitude != null ? formatCoord(s.latitude, s.longitude) : 'No location'),
    ),
  );
}

export function sightingsView(app) {
  const { sightings } = app.store;
  return h('section.view',
    h('header.top', h('h1', 'Sightings'), h('span.muted.small', `${sightings.length} total`)),
    sightings.length
      ? h('ul.rows', sightings.map((s) => h('li', sightingRow(app, s))))
      : h('div.empty-state',
        h('p.big', '🐦'),
        h('p', 'No sightings yet.'),
        h('a.btn.primary', { href: '#/capture' }, 'Capture your first bird')),
  );
}

export function sightingDetailView(app, id) {
  const s = app.store.get(id);
  if (!s) {
    return h('section.view', h('header.top', backButton(app, 'sightings')), h('p.empty', 'This sighting was deleted.'));
  }
  const species = app.catalog.get(s.speciesCode);
  const hasLocation = s.latitude != null && s.longitude != null;
  const mapHolder = hasLocation ? h('div.minimap') : null;

  const remove = async () => {
    const ok = await confirmDialog({
      title: 'Delete this sighting?',
      message: 'The photo will be removed too. If it’s your only sighting of this species, it leaves your collection.',
    });
    if (!ok) return;
    await app.store.delete([s.id]);
    app.navigate('sightings');
  };

  const node = h('section.view.detail',
    h('header.top', backButton(app, 'sightings')),
    sightingPicture(app, s, 'full', s.hasPhoto === false ? 'hero' : 'photo'),
    h('h1', s.speciesCommonName),
    h('p.sci', s.speciesSciName),
    h('p.muted', formatDate(s.capturedAt)),
    s.hasPhoto === false ? h('p.muted.small', 'Logged without a photo — field guide picture shown.') : null,
    species ? h('p', h('a', { href: `#/species/${encodeURIComponent(species.ebirdCode)}` }, 'Field guide entry ›')) : null,
    hasLocation
      ? [mapHolder, h('p.muted.small', `${formatCoord(s.latitude, s.longitude, 5)}${s.locationSource === 'photo' ? ' · from the photo' : ''}`)]
      : h('p.muted', 'No location was saved for this sighting.'),
    s.notes ? [h('h2', 'Notes'), h('p.notes', s.notes)] : null,
    h('button.btn.danger.wide', { type: 'button', onclick: remove }, 'Delete sighting'),
  );

  let map = null;
  if (mapHolder) {
    requestAnimationFrame(() => {
      smallMap(mapHolder, s).then((m) => { map = m; });
    });
  }
  return { node, cleanup: () => map?.remove() };
}
