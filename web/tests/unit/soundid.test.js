import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import {
  SAMPLE_RATE, WINDOW, addToTally, amrFrom3gp, amrKind, detections, mapLabels, mixToMono, parseLabels, rankTally, resample, sigmoid, windows,
} from '../../src/js/soundid-core.js';
import { normalizeSpecies } from '../../src/js/model.js';

const labelsPath = new URL('../../../models/birdnet/BirdNET_GLOBAL_6K_V2.4_Labels.txt', import.meta.url);
const species = JSON.parse(readFileSync(new URL('../../../DownUnderBirdCollector/Resources/Seeds/taxonomy_AU.json', import.meta.url)))
  .map(normalizeSpecies);

test('labels parse into scientific and common names, flagging non-birds', () => {
  const labels = parseLabels('Dacelo novaeguineae_Laughing Kookaburra\nEngine_Engine\n');
  assert.deepEqual(labels, [
    { sci: 'Dacelo novaeguineae', common: 'Laughing Kookaburra', isBird: true },
    { sci: 'Engine', common: 'Engine', isBird: false },
  ]);
});

test('labels map to field-guide species by scientific or common name', () => {
  const labels = parseLabels([
    'Dacelo novaeguineae_Laughing Kookaburra',
    'Calyptorhynchus funereus_Yellow-tailed Black-Cockatoo', // eBird now uses Zanda
    'Poecile atricapillus_Black-capped Chickadee',
    'Engine_Engine',
  ].join('\n'));
  assert.deepEqual(mapLabels(labels, species), ['laukoo1', 'ytblco1', null, null]);
});

test('the real BirdNET label list covers most Australian species', { skip: !existsSync(labelsPath) && 'run scripts/birdnet/fetch-model.sh' }, () => {
  const labels = parseLabels(readFileSync(labelsPath, 'utf8'));
  assert.equal(labels.length, 6522);
  const mapped = new Set(mapLabels(labels, species).filter(Boolean));
  assert.ok(mapped.size >= 360, `only ${mapped.size} species mapped`);
});

test('sigmoid and thresholded detections', () => {
  assert.equal(sigmoid(0), 0.5);
  assert.ok(sigmoid(100) <= 1 && sigmoid(-100) >= 0);
  const found = detections([2, -3, 0.1, 5], { allowed: (i) => i !== 3 });
  assert.deepEqual(found.map((d) => d.index), [0, 2]);
});

test('audio helpers', () => {
  assert.deepEqual(Array.from(mixToMono([new Float32Array([1, 0]), new Float32Array([0, 1])])), [0.5, 0.5]);
  const up = resample(new Float32Array(44100).fill(0.25), 44100);
  assert.equal(up.length, SAMPLE_RATE);
  assert.ok(Math.abs(up[1000] - 0.25) < 1e-6);
  const w = windows(new Float32Array(WINDOW * 2 + SAMPLE_RATE * 1.5));
  assert.equal(w.length, 3, 'two full windows plus a padded 1.5 s tail');
  assert.equal(windows(new Float32Array(WINDOW + 100)).length, 1, 'tails under a second are dropped');
});

test('tally keeps the best confidence and counts', () => {
  const tally = new Map();
  addToTally(tally, [{ index: 4, confidence: 0.4 }], 0);
  addToTally(tally, [{ index: 4, confidence: 0.9 }, { index: 7, confidence: 0.3 }], 3);
  const ranked = rankTally(tally);
  assert.deepEqual(ranked.map((e) => [e.index, e.best, e.count, e.lastAt]), [[4, 0.9, 2, 3], [7, 0.3, 1, 3]]);
});

const fixtureBytes = (name) => new Uint8Array(readFileSync(new URL(`../fixtures/${name}`, import.meta.url)));

test('AMR files are recognised by their header', () => {
  assert.equal(amrKind(fixtureBytes('noise-nb.amr')), 'nb');
  assert.equal(amrKind(fixtureBytes('noise-wb.amr')), 'wb');
  assert.equal(amrKind(fixtureBytes('call.wav')), null);
  assert.equal(amrKind(new Uint8Array(3)), null);
});

test('the AMR track of a 3GP recording comes out as a plain .amr file', () => {
  // noise-nb.3gp is noise-nb.amr copied into a 3GP container by ffmpeg
  assert.deepEqual(amrFrom3gp(fixtureBytes('noise-nb.3gp')), fixtureBytes('noise-nb.amr'));
  assert.equal(amrFrom3gp(fixtureBytes('noise-nb.amr')), null);
  assert.equal(amrFrom3gp(fixtureBytes('call.wav')), null);
});
