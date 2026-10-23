// Photo (or no photo) → choose species → confirm → saved. Mirrors the iOS
// capture flow; the web version always identifies by hand (no on-device model).
import { readExif } from '../exif.js';
import { processPhoto } from '../images.js';
import { REGIONS, emptyCriteria, matches } from '../model.js';
import { formatCoord, formatDate, h, speciesImage, toast } from '../ui.js';
import { speciesRow } from './guide.js';

function freshState() {
  return {
    step: 'start',          // 'start' | 'pick' | 'confirm'
    file: null,
    previewURL: null,
    source: null,           // 'camera' | 'library' | 'none' (no photo) | 'sound' (BirdNET)
    soundConfidence: null,
    takenAt: null,
    location: { status: 'none' },
    species: null,
    notes: '',
    search: '',
    saving: false,
  };
}

// The live capture screen's redraw, so async work started elsewhere (a
// location fix for a sound sighting) can update it.
let activeRerender = null;

export function captureView(app) {
  const state = app.viewState('capture', freshState);
  const root = h('section.view.capture');

  const rerender = () => {
    root.replaceChildren(...render(app, state, rerender));
  };
  activeRerender = rerender;
  rerender();
  return root;
}

/** From "Identify by sound": go straight to saving a sighting of `species`. */
export function beginSoundSighting(app, species, confidence) {
  const state = app.viewState('capture', freshState);
  reset(app, state);
  Object.assign(state, { step: 'confirm', source: 'sound', species, takenAt: new Date(), soundConfidence: confidence });
  locate(state, () => activeRerender?.());
  app.navigate('capture');
}

function reset(app, state) {
  if (state.previewURL) URL.revokeObjectURL(state.previewURL);
  Object.assign(state, freshState());
}

function render(app, state, rerender) {
  switch (state.step) {
    case 'pick': return pickStep(app, state, rerender);
    case 'confirm': return confirmStep(app, state, rerender);
    default: return startStep(app, state, rerender);
  }
}

// ── Step 1: get a photo ─────────────────────────────────────────────────────

function startStep(app, state, rerender) {
  const species = app.catalog.species(app.region);
  const have = species.filter((s) => app.store.isCollected(s.ebirdCode)).length;

  const onFile = (source) => async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    const exif = readExif(await file.arrayBuffer());
    state.file = file;
    state.previewURL = URL.createObjectURL(file);
    state.source = source;
    state.takenAt = exif.takenAt;
    state.step = 'pick';
    if (exif.coordinate) {
      state.location = { status: 'found', coordinate: exif.coordinate, source: 'photo' };
    } else if (source === 'camera') {
      locate(state, rerender);
    }
    rerender();
  };

  const cameraInput = h('input.visually-hidden', { type: 'file', accept: 'image/*', capture: 'environment', id: 'camera-input' });
  cameraInput.addEventListener('change', onFile('camera'));
  const libraryInput = h('input.visually-hidden', { type: 'file', accept: 'image/*', id: 'library-input' });
  libraryInput.addEventListener('change', onFile('library'));

  // Seen or heard but not photographed: log it here and now.
  const withoutPhoto = () => {
    state.source = 'none';
    state.takenAt = new Date();
    state.step = 'pick';
    locate(state, rerender);
    rerender();
  };

  return [
    h('header.top', h('h1', 'Capture')),
    h('div.hero-cta',
      h('div.big-icon', { 'aria-hidden': 'true' }, '📷'),
      h('h2', 'Spot a bird?'),
      h('p.muted', 'Photograph it to add it to your collection — or just log it.'),
      h('label.btn.primary.wide', { for: 'camera-input' }, 'Take photo'), cameraInput,
      h('label.btn.wide', { for: 'library-input' }, 'Choose from photos'), libraryInput,
      h('a.btn.wide', { href: '#/listen' }, '🎙 Identify by sound'),
      h('button.btn.wide', { type: 'button', onclick: withoutPhoto }, 'Log without a photo'),
      h('p.muted.small', `${have} of ${species.length} ${REGIONS[app.region]?.name ?? ''} species collected`),
    ),
  ];
}

// ── Step 2: which species? ──────────────────────────────────────────────────

function pickStep(app, state, rerender) {
  const species = app.catalog.species(app.region);
  const list = h('ul.rows');
  const criteria = emptyCriteria();

  const renderList = () => {
    criteria.search = state.search;
    const results = species.filter((s) => matches(criteria, s)).slice(0, 200);
    list.replaceChildren(...results.map((s) => h('li', speciesRow(app, s, null, () => {
      state.species = s;
      state.step = 'confirm';
      rerender();
      window.scrollTo(0, 0);
    }))));
    if (!results.length) list.append(h('li.empty', 'No matches. Try the bird’s family, e.g. “honeyeater”.'));
  };

  const search = h('input.search', {
    type: 'search', placeholder: 'Search by name or family', value: state.search, 'aria-label': 'Search species',
    autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false',
  });
  search.addEventListener('input', () => { state.search = search.value; renderList(); });
  renderList();

  return [
    h('header.top',
      h('button.back', { type: 'button', onclick: () => { reset(app, state); rerender(); } }, 'Discard'),
      h('h1', 'Which bird?')),
    state.previewURL ? h('img.preview', { src: state.previewURL, alt: 'Your photo' }) : null,
    h('p.muted.small', state.previewURL ? 'Choose the species you photographed.' : 'Choose the species you saw or heard.'),
    search,
    list,
  ];
}

// ── Step 3: confirm and save ────────────────────────────────────────────────

function confirmStep(app, state, rerender) {
  const s = state.species;
  const isNew = !app.store.isCollected(s.ebirdCode);
  const hasPhoto = Boolean(state.file);
  const takenAt = state.takenAt ?? new Date();

  // Without a photo there's no timestamp to read, so let people adjust it.
  const when = hasPhoto
    ? h('span', formatDate(takenAt))
    : h('input', { type: 'datetime-local', value: toLocalInput(takenAt), max: toLocalInput(new Date()), 'aria-label': 'When' });
  if (!hasPhoto) {
    when.addEventListener('change', () => {
      const picked = new Date(when.value);
      if (!Number.isNaN(picked.getTime())) state.takenAt = picked;
    });
  }

  const notes = h('textarea', { rows: 3, placeholder: 'What was the bird doing?', 'aria-label': 'Notes' });
  notes.value = state.notes;
  notes.addEventListener('input', () => { state.notes = notes.value; });

  const save = async () => {
    if (state.saving) return;
    state.saving = true;
    rerender();
    try {
      const photo = hasPhoto ? await processPhoto(state.file) : null;
      const loc = state.location.status === 'found' ? state.location : null;
      await app.store.add({
        species: s,
        photo,
        capturedAt: state.takenAt ?? takenAt,
        coordinate: loc?.coordinate ?? null,
        accuracy: loc?.accuracy ?? null,
        locationSource: loc?.source ?? null,
        notes: state.notes.trim(),
        identifiedBy: state.source === 'sound' ? 'sound' : null,
        mlTop: state.source === 'sound' ? { code: s.ebirdCode, confidence: state.soundConfidence } : null,
      });
      const total = app.catalog.species(app.region).length;
      const have = app.catalog.species(app.region).filter((x) => app.store.isCollected(x.ebirdCode)).length;
      reset(app, state);
      celebrate(isNew
        ? { title: 'New species collected!', message: `${s.commonName} is now in your collection — ${have} of ${total}.` }
        : { title: 'Sighting saved', message: `Another ${s.commonName} for your log.` });
      rerender();
    } catch (err) {
      state.saving = false;
      toast(`Couldn’t save: ${err.message}`);
      rerender();
    }
  };

  return [
    h('header.top',
      state.source === 'sound'
        ? h('a.back', { href: '#/listen' }, '‹ Sounds')
        : h('button.back', { type: 'button', onclick: () => { state.step = 'pick'; rerender(); } }, '‹ Species'),
      h('h1', 'Save sighting')),
    hasPhoto
      ? h('img.preview', { src: state.previewURL, alt: 'Your photo' })
      : speciesImage(app.catalog.picture(s), s.commonName, 'preview-species'),
    h('div.form',
      h('div.field', h('span.label', 'Species'),
        h('strong', s.commonName), h('em.muted.small', s.scientificName),
        h(`span.pill${isNew ? '.accent' : ''}`, isNew ? '✨ New for your collection!' : 'Already in your collection')),
      h('label.field', h('span.label', 'When'), when),
      hasPhoto ? null : h('p.muted.small', state.source === 'sound'
        ? `Identified by sound with BirdNET (${Math.round((state.soundConfidence ?? 0) * 100)}% confidence).`
        : 'Logged without a photo — the field guide picture stands in for it.'),
      h('div.field', h('span.label', 'Where'), locationBlock(state, rerender),
        h('span.muted.small', 'Locations are only stored with your sightings, in this browser.')),
      h('label.field', h('span.label', 'Notes'), notes),
      h('button.btn.primary.wide', { type: 'button', onclick: save, disabled: state.saving }, state.saving ? 'Saving…' : 'Save sighting'),
    ),
  ];
}

function locationBlock(state, rerender) {
  const loc = state.location;
  const useCurrent = h('button.btn.small', { type: 'button', onclick: () => locate(state, rerender) }, 'Use my current location');
  switch (loc.status) {
    case 'locating':
      return h('span.muted', 'Getting your location…');
    case 'found':
      return h('div',
        h('span.mono', formatCoord(loc.coordinate.lat, loc.coordinate.lon, 5)), ' ',
        h('span.muted.small', loc.source === 'photo' ? 'from the photo' : `your location${loc.accuracy ? `, ±${Math.round(loc.accuracy)} m` : ''}`), ' ',
        h('button.link', { type: 'button', onclick: () => { state.location = { status: 'none' }; rerender(); } }, 'Remove'));
    case 'error':
      return h('div', h('span.muted', loc.message), ' ', useCurrent);
    default:
      return h('div',
        h('span.muted', state.source === 'library' ? 'This photo has no location. ' : 'No location. '),
        useCurrent);
  }
}

function locate(state, rerender) {
  // Location only shows on the Save step; redrawing the species picker
  // mid-typing would drop keyboard focus.
  const refresh = () => {
    if (state.step === 'confirm') rerender();
  };
  if (!('geolocation' in navigator)) {
    state.location = { status: 'error', message: 'Location isn’t available in this browser.' };
    refresh();
    return;
  }
  state.location = { status: 'locating' };
  refresh();
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      state.location = {
        status: 'found',
        coordinate: { lat: pos.coords.latitude, lon: pos.coords.longitude },
        accuracy: pos.coords.accuracy,
        source: 'device',
      };
      refresh();
    },
    (err) => {
      state.location = {
        status: 'error',
        message: err.code === err.PERMISSION_DENIED ? 'Location permission is off.' : 'Couldn’t get a location fix.',
      };
      refresh();
    },
    { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 },
  );
}

function celebrate({ title, message }) {
  const dialog = h('dialog.sheet.confirm.celebrate',
    h('div.big-icon', { 'aria-hidden': 'true' }, '🎉'),
    h('h2', title),
    h('p', message),
    h('div.row.end', h('button.btn.primary', { type: 'button', onclick: () => dialog.close() }, 'Nice!')));
  dialog.addEventListener('close', () => dialog.remove());
  document.body.append(dialog);
  dialog.showModal();
}

/** Date -> "YYYY-MM-DDTHH:MM" in local time, for <input type="datetime-local">. */
function toLocalInput(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
