import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { centreSquare, dequantize, latinStem, mapLabels, parseLabels, suggestions } from '../../src/js/photoid-core.js';
import { normalizeSpecies } from '../../src/js/model.js';

const resources = new URL('../../../DownUnderBirdCollector/Resources/', import.meta.url);
const species = JSON.parse(readFileSync(new URL('Seeds/taxonomy_AU.json', resources))).map(normalizeSpecies);
const labels = parseLabels(readFileSync(new URL('ML/BirdPhotoClassifier_labels.txt', resources), 'utf8'));

test('labels parse into scientific and common names', () => {
  assert.equal(labels.length, 965);
  assert.deepEqual(parseLabels('Dacelo novaeguineae (Laughing Kookaburra)\nbackground\n'), [
    { sci: 'Dacelo novaeguineae', common: 'Laughing Kookaburra' },
    { sci: 'background', common: '' },
  ]);
});

test('Latin gender endings are ignored when matching', () => {
  assert.equal(latinStem('Threskiornis moluccus'), latinStem('Threskiornis molucca'));
});

test('77 field-guide species are recognisable, including renamed ones and subspecies', () => {
  const codes = mapLabels(labels, species);
  assert.equal(new Set(codes.filter(Boolean)).size, 77);
  const codeOf = (sci) => codes[labels.findIndex((l) => l.sci === sci)];
  assert.equal(codeOf('Dacelo novaeguineae'), 'laukoo1');
  assert.equal(codeOf('Threskiornis moluccus'), 'auwhib1', 'Australian Ibis = Australian White Ibis');
  assert.equal(codeOf('Ardea alba modesta'), codeOf('Ardea alba'), 'Eastern Great Egret is the Great Egret');
  assert.ok(codeOf('Ardea alba modesta'));
  assert.equal(codeOf('Turdus migratorius'), null);
  assert.equal(codeOf('background'), null);
});

test('suggestions are field-guide birds only, best first, flagged when unsure', () => {
  const codes = [null, 'laukoo1', 'galah', null, 'laukoo1'];
  assert.deepEqual(suggestions([0.01, 0.8, 0.06, 0.1, 0.03], codes),
    { suggestions: [{ code: 'laukoo1', confidence: 0.8 }, { code: 'galah', confidence: 0.06 }], unsure: false });
  // Best guess is a bird the field guide doesn't have (e.g. American Robin).
  const foreign = suggestions([0.9, 0.04, 0.06, 0, 0], codes);
  assert.deepEqual(foreign.suggestions.map((s) => s.code), ['galah']);
  assert.equal(foreign.unsure, true);
  assert.deepEqual(suggestions([0.97, 0.01, 0.02, 0, 0], codes).suggestions, []);
});

test('dequantize and centre crop', () => {
  assert.deepEqual(Array.from(dequantize(new Uint8Array([0, 128, 255]))), [0, 0.5, 255 / 256]);
  assert.deepEqual(centreSquare(400, 286), { sx: 57, sy: 0, size: 286 });
  assert.deepEqual(centreSquare(300, 500), { sx: 0, sy: 100, size: 300 });
});
