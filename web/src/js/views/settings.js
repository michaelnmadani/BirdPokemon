import { REGIONS } from '../model.js';
import { getApiKey, setApiKey } from '../ebird.js';
import { MODEL_MB, isAvailable, isDownloaded, removeDownload } from '../soundid.js';
import { backButton, confirmDialog, h, toast } from '../ui.js';

const PHOTO_CACHE = 'species-photos';

export function settingsView(app) {
  const species = app.catalog.species(app.region);
  const photoURLs = [...new Set(app.catalog.regions.flatMap((r) => app.catalog.species(r))
    .flatMap((s) => [s.thumbnailURL, app.catalog.art.get(s.ebirdCode)?.url]).filter(Boolean))];

  const regionPicker = app.catalog.regions.length > 1
    ? (() => {
      const select = h('select', { 'aria-label': 'Region' },
        app.catalog.regions.map((code) => h('option', { value: code, selected: code === app.region }, `${REGIONS[code]?.flag ?? ''} ${REGIONS[code]?.name ?? code}`)));
      select.addEventListener('change', () => { app.setRegion(select.value); app.render(); });
      return select;
    })()
    : h('span', `${REGIONS[app.region]?.flag ?? ''} ${REGIONS[app.region]?.name ?? app.region}`);

  const offlineStatus = h('span.muted');
  const storageStatus = h('span.muted');
  const photoStatus = h('span.muted');

  const updateStatus = async () => {
    offlineStatus.textContent = navigator.serviceWorker?.controller ? '✓ Ready to use offline' : 'Not installed yet — reload once while online';
    const estimate = await navigator.storage?.estimate?.();
    storageStatus.textContent = estimate ? `${(estimate.usage / 1e6).toFixed(1)} MB used` : '';
    if ('caches' in window) {
      const cache = await caches.open(PHOTO_CACHE);
      const keys = await cache.keys();
      photoStatus.textContent = `${keys.length} of ${photoURLs.length} species photos saved for offline`;
    }
  };
  updateStatus();

  const downloadButton = h('button.btn.small', { type: 'button' }, 'Download species photos (~25 MB)');
  downloadButton.addEventListener('click', async () => {
    downloadButton.disabled = true;
    const cache = await caches.open(PHOTO_CACHE);
    let done = 0;
    let failed = 0;
    const queue = [...photoURLs];
    const worker = async () => {
      while (queue.length) {
        const url = queue.shift();
        try {
          if (!(await cache.match(url))) {
            const resp = await fetch(url, { mode: 'cors' });
            if (resp.ok) await cache.put(url, resp);
            else failed++;
          }
        } catch {
          failed++;
        }
        done++;
        photoStatus.textContent = `Saving photos… ${done} / ${photoURLs.length}`;
      }
    };
    await Promise.all(Array.from({ length: 6 }, worker));
    downloadButton.disabled = false;
    toast(failed ? `${failed} photos couldn’t be downloaded — try again online.` : 'All species photos saved for offline use.');
    updateStatus();
  });

  const deleteAll = async () => {
    if (!app.store.sightings.length) return toast('There are no sightings to delete.');
    const ok = await confirmDialog({ title: 'Delete all sightings?', message: 'This removes every sighting and photo saved in this browser and can’t be undone.', confirm: 'Delete everything' });
    if (!ok) return;
    await app.store.deleteAll();
    toast('All sightings deleted.');
  };

  return h('section.view.settings',
    h('header.top', backButton(app, 'collection'), h('h1', 'Settings')),

    h('h2', 'Region'),
    h('div.card-list', h('div.item', h('span', 'Region'), regionPicker),
      app.catalog.regions.length < 2 ? h('p.muted.small', 'New Zealand, the UK and the US are planned for later versions.') : null),

    h('h2', 'Your data'),
    h('div.card-list',
      h('div.item', h('span', 'Sightings'), h('strong', String(app.store.sightings.length))),
      h('div.item', h('span', 'Species collected'), h('strong', `${species.filter((s) => app.store.isCollected(s.ebirdCode)).length} of ${species.length}`)),
      h('div.item', h('span', 'Stored'), h('span.muted', 'In this browser only')),
      h('div.item', h('span', 'Storage'), storageStatus),
      h('button.btn.danger.wide', { type: 'button', onclick: deleteAll }, 'Delete all sightings'),
    ),

    app.catalog.hasArt ? [h('h2', 'Bird pictures'), pictureStyleCard(app)] : null,

    h('h2', 'Nearby birds (eBird)'),
    ebirdKeyCard(),

    h('h2', 'Sound ID (BirdNET)'),
    soundCard(app),

    h('h2', 'Offline'),
    h('div.card-list',
      h('div.item', h('span', 'App'), offlineStatus),
      h('div.item', h('span', 'Photos'), photoStatus),
      downloadButton,
      h('p.muted.small', 'Species photos you’ve already looked at are kept automatically. Download them all before heading somewhere without signal.'),
    ),

    h('h2', 'Install on iPhone'),
    h('p.muted', 'In Safari, tap Share → “Add to Home Screen”. The app then opens full-screen and works without a connection.'),

    h('h2', 'About'),
    h('a.btn.wide', { href: '#/credits' }, 'Photo, painting & sound credits'),
    h('p.muted.small', 'This is the web test version of Down Under Bird Collector. Species data from eBird (Cornell Lab of Ornithology). Species photos by iNaturalist contributors, credited on each species page. Map © OpenStreetMap contributors. Bird calls from xeno-canto and iNaturalist recordists, credited under each player. Sound ID by BirdNET (Cornell Lab of Ornithology & Chemnitz University of Technology), model licensed CC BY-NC-SA 4.0.'),
    app.catalog.issues.length ? h('ul.issues', app.catalog.issues.map((i) => h('li', i))) : null,
    h('p.muted.small', `Build ${document.documentElement.dataset.build ?? 'dev'}`),
  );
}

function pictureStyleCard(app) {
  const options = [['watercolour', 'Watercolour'], ['photo', 'Photo']];
  const group = h('div.segmented.two', { role: 'radiogroup', 'aria-label': 'Bird pictures' }, options.map(([id, label]) =>
    h('button', {
      type: 'button', role: 'radio', 'aria-checked': String(app.catalog.pictureStyle === id), 'aria-selected': String(app.catalog.pictureStyle === id),
      onclick: () => {
        app.catalog.setPictureStyle(id);
        group.querySelectorAll('button').forEach((b, i) => {
          b.setAttribute('aria-checked', String(options[i][0] === id));
          b.setAttribute('aria-selected', String(options[i][0] === id));
        });
      },
    }, label)));
  return h('div.card-list',
    group,
    h('p.muted.small', `Watercolours of ${app.catalog.art.size} species, painted from the field guide photos. Species without one show the photo. Your own sightings always show your photos.`));
}

function soundCard(app) {
  const status = h('span.muted', 'Checking…');
  const remove = h('button.btn.small', { type: 'button', hidden: true }, 'Remove download');
  const refresh = async () => {
    const [available, downloaded] = await Promise.all([isAvailable(), isDownloaded()]);
    status.textContent = !available ? 'Not included in this build'
      : downloaded ? '✓ Downloaded — works offline' : `Downloads on first use (${MODEL_MB} MB)`;
    remove.hidden = !downloaded;
  };
  remove.addEventListener('click', async () => {
    await removeDownload();
    toast('Sound ID model removed. It downloads again next time you use it.');
    refresh();
  });
  refresh();
  return h('div.card-list',
    h('div.item', h('span', 'Model'), status),
    h('p.muted.small', 'Identifies birds from their calls on your device — audio is never uploaded. ',
      h('a', { href: '#/listen' }, 'Identify by sound')),
    remove,
  );
}

function ebirdKeyCard() {
  const input = h('input.search', {
    type: 'password', placeholder: 'Paste your eBird API key', value: getApiKey(),
    autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false', 'aria-label': 'eBird API key',
  });
  const save = () => {
    setApiKey(input.value.trim());
    toast(input.value.trim() ? 'eBird key saved — the Nearby tab will include recent reports.' : 'eBird key removed.');
  };
  return h('div.card-list',
    h('p.muted.small', 'The Nearby tab can include what other birdwatchers reported within 5 km in the last 30 days. Get a free personal key at ',
      h('a', { href: 'https://ebird.org/api/keygen', target: '_blank', rel: 'noopener' }, 'ebird.org/api/keygen'),
      '. It’s stored only in this browser.'),
    input,
    h('div.row',
      h('button.btn.small', { type: 'button', onclick: () => { input.type = input.type === 'password' ? 'text' : 'password'; } }, 'Show'),
      h('span.spacer'),
      h('button.btn.small.primary', { type: 'button', onclick: save }, 'Save key')),
  );
}
