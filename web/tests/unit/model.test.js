import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  activeFilterCount, collectedCodes, emptyCriteria, familyOptions, latestBySpecies,
  licenceLabel, matches, normalizeSpecies, photoCredit,
} from '../../src/js/model.js';
import { parseExifDate, readExif } from '../../src/js/exif.js';

const taxonomy = JSON.parse(readFileSync(new URL('../../../DownUnderBirdCollector/Resources/Seeds/taxonomy_AU.json', import.meta.url)));
const species = taxonomy.map(normalizeSpecies);

test('the bundled Australian list loads completely', () => {
  assert.ok(species.length >= 500);
  assert.ok(species.every(Boolean));
  assert.equal(species.find((s) => s.ebirdCode === 'emu1').commonName, 'Emu');
});

test('normalizeSpecies is lenient like the iOS decoder', () => {
  const s = normalizeSpecies({ ebirdCode: 'x', commonName: 'X', sizeCategory: 'giant', primaryColors: ['rufous', 'grey', 'grey', 'streaked'] });
  assert.deepEqual(s.primaryColors, ['orange', 'gray']);
  assert.equal(s.sizeCategory, 'medium');
  assert.equal(s.ebirdURL, 'https://ebird.org/species/x');
  assert.equal(normalizeSpecies({ commonName: 'no code' }), null);
});

test('filters combine like FilterCriteria on iOS', () => {
  const c = emptyCriteria();
  c.search = 'kookaburra';
  const kookas = species.filter((s) => matches(c, s));
  assert.ok(kookas.length >= 2);
  assert.ok(kookas.every((s) => /kookaburra/i.test(s.commonName)));

  c.search = '';
  c.colors.add('blue');
  c.sizes.add('tiny');
  assert.ok(species.filter((s) => matches(c, s)).every((s) => s.sizeCategory === 'tiny' && s.primaryColors.includes('blue')));
  assert.equal(activeFilterCount(c), 2);
});

test('family search uses common family names', () => {
  const c = emptyCriteria();
  c.search = 'honeyeater';
  assert.ok(species.filter((s) => matches(c, s)).length > 10);
  assert.ok(familyOptions(species).some((f) => f.family === 'Meliphagidae'));
});

test('collected and latest sightings', () => {
  const sightings = [
    { id: 'a', speciesCode: 'galah', capturedAt: '2025-01-01T00:00:00.000Z' },
    { id: 'b', speciesCode: 'galah', capturedAt: '2025-03-01T00:00:00.000Z' },
    { id: 'c', speciesCode: 'emu1', capturedAt: '2025-02-01T00:00:00.000Z' },
  ];
  assert.deepEqual([...collectedCodes(sightings)].sort(), ['emu1', 'galah']);
  assert.equal(latestBySpecies(sightings).get('galah').id, 'b');
});

test('photo credit formatting', () => {
  assert.equal(licenceLabel('cc-by-nc'), 'CC BY-NC');
  assert.equal(photoCredit({ thumbnailAttribution: '© Jane', thumbnailLicense: 'cc0' }), '© Jane · CC0');
  assert.equal(photoCredit({}), null);
});

test('EXIF GPS and capture time are read from a JPEG', () => {
  const buf = readFileSync(new URL('../fixtures/bird-with-gps.jpg', import.meta.url));
  const { takenAt, coordinate } = readExif(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
  assert.ok(Math.abs(coordinate.lat - -27.4698) < 0.0001);
  assert.ok(Math.abs(coordinate.lon - 153.0251) < 0.0001);
  assert.equal(takenAt.toISOString(), '2025-09-13T21:30:00.000Z');
});

test('JPEG without metadata reads as empty', () => {
  const buf = readFileSync(new URL('../fixtures/bird-no-metadata.jpg', import.meta.url));
  assert.deepEqual(readExif(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)), { takenAt: null, coordinate: null });
  assert.equal(parseExifDate('garbage'), null);
});
