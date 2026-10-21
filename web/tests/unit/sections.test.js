import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildGroups } from '../../src/js/groups.js';
import { normalizeSpecies } from '../../src/js/model.js';
import { sections } from '../../src/js/sections.js';

const seeds = new URL('../../../DownUnderBirdCollector/Resources/Seeds/', import.meta.url);
const species = JSON.parse(readFileSync(new URL('taxonomy_AU.json', seeds))).map(normalizeSpecies);
const { groups } = buildGroups(JSON.parse(readFileSync(new URL('groups.json', seeds))), species);
const total = (list) => list.reduce((n, s) => n + s.species.length, 0);
const sectionOf = (list, name) => list.find((s) => s.species.some((sp) => sp.commonName === name));

test('no grouping is one untitled section', () => {
  const out = sections(species, 'none');
  assert.equal(out.length, 1);
  assert.equal(out[0].title, null);
  assert.equal(out[0].species.length, species.length);
});

for (const by of ['group', 'family', 'size', 'colour']) {
  test(`grouping by ${by} lists every species exactly once`, () => {
    const out = sections(species, by, groups);
    assert.equal(total(out), species.length);
    assert.equal(new Set(out.flatMap((s) => s.species.map((sp) => sp.ebirdCode))).size, species.length);
    assert.ok(out.every((s) => s.species.length && s.title));
  });
}

test('bird groups follow the curated order, with each bird in its first group', () => {
  const out = sections(species, 'group', groups);
  assert.equal(out[0].title, 'Flightless birds');
  assert.equal(sectionOf(out, 'Emu').id, 'flightless');
  assert.equal(sectionOf(out, 'Galah').id, 'parrots');
  assert.equal(sectionOf(out, 'Rock Dove').id, 'pigeons', 'introduced pigeons stay with pigeons');
});

test('sizes run tiny to huge and colours follow the palette', () => {
  const bySize = sections(species, 'size');
  assert.deepEqual(bySize.map((s) => s.id), ['tiny', 'small', 'medium', 'large', 'huge'].filter((id) => bySize.some((s) => s.id === id)));
  assert.equal(sectionOf(bySize, 'Emu').id, 'huge');
  const byColour = sections(species, 'colour');
  assert.ok(byColour.every((s) => s.id === 'unknown' || s.swatch));
  assert.ok(byColour.some((s) => s.title === 'Grey'));
});

test('families keep taxonomic order and only include what is passed in', () => {
  const some = species.filter((s) => ['Emu', 'Galah', 'Sulphur-crested Cockatoo'].includes(s.commonName));
  const out = sections(some, 'family');
  assert.equal(out.length, 2);
  assert.equal(out[1].species.length, 2);
  assert.equal(out[0].species[0].commonName, 'Emu');
});
