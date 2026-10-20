// "Identify by sound": listen through the microphone (or analyse a recording)
// with BirdNET and list the birds heard, ready to log as sightings.
import { MODEL_MB, Listener, SoundID, decodeFile, isAvailable, isDownloaded } from '../soundid.js';
import { addToTally, detections, rankTally, windows } from '../soundid-core.js';
import { backButton, h, speciesImage, toast } from '../ui.js';
import { beginSoundSighting } from './capture.js';

let engine = null;        // loaded once per page session
let engineLoading = null;
let listener = null;

function freshState() {
  return {
    mode: 'idle',           // 'idle' | 'loading' | 'listening' | 'analysing'
    progress: 0,
    tally: new Map(),
    windowsDone: 0,
    fieldGuideOnly: true,
    error: '',
    source: '',             // 'mic' | file name
    available: null,
    downloaded: null,
  };
}

async function ensureEngine(app, state, rerender) {
  if (engine) return engine;
  state.mode = 'loading';
  state.progress = 0;
  rerender();
  engineLoading ??= SoundID.load(app.catalog.species(app.region), (p) => {
    state.progress = p;
    rerender();
  });
  try {
    engine = await engineLoading;
    state.downloaded = true;
    return engine;
  } catch (err) {
    engineLoading = null;
    throw err;
  }
}

/** Which classes to show: birds, optionally only field-guide species. */
function allowed(state) {
  return (i) => engine.labels[i].isBird && (!state.fieldGuideOnly || engine.codes[i] !== null);
}

async function processWindow(state, samples, atSeconds) {
  const logits = await engine.classify(samples);
  // Tally every bird; the field-guide filter applies when showing results.
  addToTally(state.tally, detections(logits, { allowed: (i) => engine.labels[i].isBird }), atSeconds);
  state.windowsDone += 1;
}

export function listenView(app) {
  const state = app.viewState('listen', freshState);
  const root = h('section.view.listen');
  const rerender = () => root.replaceChildren(...render(app, state, rerender).flat().filter(Boolean));

  if (state.available === null) {
    Promise.all([isAvailable(), isDownloaded()]).then(([available, downloaded]) => {
      Object.assign(state, { available, downloaded });
      rerender();
    });
  }
  rerender();
  return { node: root, cleanup: () => stopListening(state) };
}

function stopListening(state) {
  listener?.stop();
  listener = null;
  if (state.mode === 'listening') state.mode = 'idle';
}

async function startListening(app, state, rerender) {
  try {
    await ensureEngine(app, state, rerender);
    state.tally = new Map();
    state.windowsDone = 0;
    state.error = '';
    state.source = 'mic';
    listener = new Listener();
    await listener.start(async (samples, at) => {
      await processWindow(state, samples, at);
      rerender();
    });
    state.mode = 'listening';
  } catch (err) {
    stopListening(state);
    state.mode = 'idle';
    state.error = err.name === 'NotAllowedError'
      ? 'Microphone access is off. Allow it to identify birds by sound.'
      : `Couldn’t start listening: ${err.message}`;
  }
  rerender();
}

async function analyseFile(app, state, rerender, file) {
  try {
    await ensureEngine(app, state, rerender);
    Object.assign(state, { mode: 'analysing', tally: new Map(), windowsDone: 0, error: '', source: file.name, progress: 0 });
    rerender();
    const chunks = windows(await decodeFile(file));
    for (const [i, chunk] of chunks.entries()) {
      await processWindow(state, chunk.samples, chunk.start / 48000);
      state.progress = (i + 1) / chunks.length;
      rerender();
    }
    state.mode = 'idle';
    if (!rankTally(state.tally).some((e) => allowed(state)(e.index))) toast('No birds recognised in that recording.');
  } catch (err) {
    state.mode = 'idle';
    state.error = `Couldn’t analyse that recording: ${err.message}`;
  }
  rerender();
}

function render(app, state, rerender) {
  const header = h('header.top', backButton(app, 'capture', 'Capture'), h('h1', 'Identify by sound'));
  const credit = h('p.muted.small', 'Powered by ', h('a', { href: 'https://birdnet.cornell.edu', target: '_blank', rel: 'noopener' }, 'BirdNET'),
    ' (Cornell Lab of Ornithology & Chemnitz University of Technology). Runs on your device — audio is never uploaded.');

  if (state.available === false) {
    return [header, h('p.notice', 'Sound identification isn’t included in this build of the web app.'), credit];
  }

  const busy = state.mode === 'loading' || state.mode === 'analysing';
  const fileInput = h('input.visually-hidden', { type: 'file', accept: 'audio/*', id: 'sound-file', disabled: busy || state.mode === 'listening' });
  fileInput.addEventListener('change', (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file) analyseFile(app, state, rerender, file);
  });

  const toggle = h('input', { type: 'checkbox', checked: state.fieldGuideOnly });
  toggle.addEventListener('change', () => {
    state.fieldGuideOnly = toggle.checked;
    rerender();
  });

  const listenButton = state.mode === 'listening'
    ? h('button.btn.danger.wide', { type: 'button', onclick: () => { stopListening(state); rerender(); } }, '■ Stop listening')
    : h('button.btn.primary.wide', { type: 'button', disabled: busy, onclick: () => startListening(app, state, rerender) }, '🎙 Start listening');

  return [
    header,
    credit,
    state.downloaded === false && state.mode !== 'loading'
      ? h('p.notice', `The first time, sound ID downloads a ${MODEL_MB} MB model. After that it works offline.`)
      : null,
    listenButton,
    h('label.btn.wide', { for: 'sound-file', 'aria-disabled': String(busy || state.mode === 'listening') }, 'Analyse a recording'),
    fileInput,
    h('label.check.inline', toggle, h('span', 'Only birds in the field guide')),
    status(state),
    state.error ? h('p.notice', state.error) : null,
    results(app, state),
  ];
}

function status(state) {
  switch (state.mode) {
    case 'loading':
      return h('div.progress-card', h('span', `Loading BirdNET… ${Math.round(state.progress * 100)}%`),
        h('progress', { max: 1, value: state.progress }));
    case 'listening':
      return h('p.listening', h('span.pulse', { 'aria-hidden': 'true' }), ` Listening… ${state.windowsDone * 3}s analysed`);
    case 'analysing':
      return h('div.progress-card', h('span', `Analysing ${state.source}… ${Math.round(state.progress * 100)}%`),
        h('progress', { max: 1, value: state.progress }));
    default:
      return state.windowsDone ? h('p.muted.small', `${state.windowsDone * 3}s of audio analysed${state.source && state.source !== 'mic' ? ` from ${state.source}` : ''}.`) : null;
  }
}

function results(app, state) {
  if (!engine || !state.tally.size) return null;
  const birds = rankTally(state.tally);
  const ranked = birds.filter((e) => allowed(state)(e.index));
  if (!ranked.length) {
    return birds.length
      ? h('p.muted.small', `No field-guide birds heard. ${birds.length} other bird${birds.length === 1 ? '' : 's'} — untick “Only birds in the field guide” to see ${birds.length === 1 ? 'it' : 'them'}.`)
      : null;
  }
  return [h('h2', 'Heard'), h('ul.rows', ranked.map((entry) => h('li', resultRow(app, entry))))];
}

function resultRow(app, entry) {
  const label = engine.labels[entry.index];
  const code = engine.codes[entry.index];
  const species = code ? app.catalog.get(code) : null;
  const percent = Math.round(entry.best * 100);
  const collected = code && app.store.isCollected(code);
  return h('div.species-row.heard',
    h('div.row-img', speciesImage(species?.thumbnailURL, label.common, 'thumb'),
      collected ? h('span.seal.small', { 'aria-hidden': 'true' }, '✓') : null),
    h('div.row-text',
      species ? h('a', { href: `#/species/${encodeURIComponent(code)}` }, h('strong', species.commonName)) : h('strong', label.common),
      h('em.muted.small', label.sci),
      h('span.meta', `${percent}% · heard ${entry.count}× · at ${formatSeconds(entry.lastAt)}`),
      species ? null : h('span.meta', 'Not in the field guide'),
      h('span.confidence', { style: { width: `${percent}%` } }),
    ),
    species
      ? h('button.btn.small.primary', { type: 'button', onclick: () => beginSoundSighting(app, species, entry.best) }, 'Log it')
      : null,
  );
}

function formatSeconds(s) {
  return `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
}
