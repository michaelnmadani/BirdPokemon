// Every photo, watercolour and recording in the field guide with its creator
// and licence, as the Creative Commons licences require.
import { licenceLabel } from '../model.js';
import { backButton, h } from '../ui.js';

const LICENCE_URLS = {
  cc0: 'https://creativecommons.org/publicdomain/zero/1.0/',
  'cc-by': 'https://creativecommons.org/licenses/by/4.0/',
  'cc-by-sa': 'https://creativecommons.org/licenses/by-sa/4.0/',
  'cc-by-nc': 'https://creativecommons.org/licenses/by-nc/4.0/',
  'cc-by-nc-sa': 'https://creativecommons.org/licenses/by-nc-sa/4.0/',
  'cc-by-nd': 'https://creativecommons.org/licenses/by-nd/4.0/',
  'cc-by-nc-nd': 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
};

function licenceLink(code) {
  const label = licenceLabel(code);
  if (!label) return null;
  const url = LICENCE_URLS[code.toLowerCase()];
  return url ? h('a', { href: url, target: '_blank', rel: 'noopener license' }, label) : label;
}

function line(kind, text, licence, link) {
  return h('p.credit.left',
    h('strong', `${kind}: `),
    link ? h('a', { href: link, target: '_blank', rel: 'noopener' }, text) : text,
    licence ? [' · ', licenceLink(licence)] : null);
}

function entry(app, s) {
  const art = app.catalog.art.get(s.ebirdCode);
  const photo = s.thumbnailURL
    ? line('Photo', (s.thumbnailAttribution ?? 'iNaturalist observer'), s.thumbnailLicense, null)
    : h('p.credit.left', h('strong', 'Photo: '), 'none yet');
  const painting = art
    ? h('p.credit.left', h('strong', 'Watercolour: '), 'adapted from the photo above',
      art.license ? [' · ', licenceLink(art.license)] : null)
    : null;
  const call = s.callURL
    ? line('Call', `${s.callAttribution ?? 'Recording'} via ${s.callSource === 'xeno-canto' ? 'xeno-canto' : 'iNaturalist'}`,
      s.callLicense, s.callPageURL)
    : null;
  return h('li.credit-entry', h('a', { href: `#/species/${encodeURIComponent(s.ebirdCode)}` }, h('strong', s.commonName)),
    photo, painting, call);
}

export function creditsView(app) {
  const species = app.catalog.species(app.region);
  const list = h('ul.credit-list');
  const search = h('input.search', { type: 'search', placeholder: 'Search credits', 'aria-label': 'Search credits' });
  const render = () => {
    const q = search.value.trim().toLowerCase();
    const shown = species.filter((s) => !q || [s.commonName, s.thumbnailAttribution, s.callAttribution]
      .some((v) => v?.toLowerCase().includes(q)));
    list.replaceChildren(...shown.map((s) => entry(app, s)));
  };
  search.addEventListener('input', render);
  render();

  const photos = species.filter((s) => s.thumbnailURL).length;
  const calls = species.filter((s) => s.callURL).length;
  const paintings = species.filter((s) => app.catalog.art.has(s.ebirdCode)).length;
  return h('section.view.credits',
    h('header.top', backButton(app, 'settings', 'Settings'), h('h1', 'Credits')),
    h('p.muted.small',
      `${photos} species photos by iNaturalist contributors, ${calls} recordings from iNaturalist and xeno-canto`,
      paintings ? `, and ${paintings} watercolours painted from those photos` : '',
      '. Each is used under the Creative Commons licence shown. Watercolours are adaptations of the credited photo and share its licence.'),
    search,
    list,
    h('h2', 'Also'),
    h('p.muted.small', 'Species names and taxonomy: eBird / Clements Checklist (Cornell Lab of Ornithology). Sound identification: BirdNET (K. Lisa Yang Center for Conservation Bioacoustics, Cornell Lab of Ornithology & Chemnitz University of Technology), CC BY-NC-SA 4.0. Maps © OpenStreetMap contributors. Size estimates from AVONET (CC BY 4.0).'),
  );
}
