import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildGroups, genusLabel, groupsMatching, plural } from '../../src/js/groups.js';
import { normalizeSpecies } from '../../src/js/model.js';

const seeds = new URL('../../../DownUnderBirdCollector/Resources/Seeds/', import.meta.url);
const species = JSON.parse(readFileSync(new URL('taxonomy_AU.json', seeds))).map(normalizeSpecies);
const definitions = JSON.parse(readFileSync(new URL('groups.json', seeds)));
const { groups, byCode } = buildGroups(definitions, species);
const group = (id) => groups.find((g) => g.id === id);
const names = (g) => g.species.map((s) => s.commonName);

test('plural handles bird-name endings', () => {
  assert.equal(plural('Rosella'), 'Rosellas');
  assert.equal(plural('Finch'), 'Finches');
  assert.equal(plural('Ibis'), 'Ibises');
  assert.equal(plural('Goose'), 'Geese');
  assert.equal(plural('Black-Cockatoo'), 'Black-Cockatoos');
  assert.equal(plural('Quail-thrush'), 'Quail-thrushes');
});

test('genus labels come from the shared part of common names', () => {
  assert.equal(genusLabel(['Crimson Rosella', 'Eastern Rosella', 'Green Rosella']), 'Rosellas');
  assert.equal(genusLabel(['Great Egret', 'Pacific Heron', 'Little Egret', 'Great-billed Heron']), 'Egrets & Herons');
  assert.equal(genusLabel(['Carpentarian Grasswren (alt)', 'Dusky Grasswren']), 'Grasswrens');
});

test('flightless birds are Emu, Cassowary and Little Penguin', () => {
  assert.deepEqual(names(group('flightless')).sort(), ['Emu', 'Little Penguin', 'Southern Cassowary']);
});

test('parrots group covers cockatoos and lorikeets', () => {
  const parrots = names(group('parrots'));
  for (const n of ['Galah', 'Rainbow Lorikeet', 'Sulphur-crested Cockatoo', 'Budgerigar']) assert.ok(parrots.includes(n), n);
});

test('shorebirds exclude gulls/terns and buttonquails', () => {
  const shore = names(group('shorebirds'));
  assert.ok(shore.includes('Masked Lapwing'));
  assert.ok(!shore.includes('Silver Gull'));
  assert.ok(names(group('seabirds')).includes('Silver Gull'));
  assert.ok(names(group('gamebirds')).includes('Painted Buttonquail'));
});

test('introduced species group uses real codes', () => {
  assert.deepEqual(names(group('introduced')).sort(),
    ['Common Blackbird', 'Common Myna', 'Common Starling', 'House Sparrow', 'Rock Dove', 'Spotted Turtle-Dove']);
});

test('every species is in at least one bird group', () => {
  for (const s of species) {
    assert.ok((byCode.get(s.ebirdCode) ?? []).some((g) => g.kind === 'group'), s.commonName);
  }
});

test('genera with 2+ species become groups', () => {
  const rosellas = groups.find((g) => g.genus === 'Platycercus');
  assert.equal(rosellas.name, 'Rosellas');
  assert.ok(rosellas.species.length >= 5);
  assert.equal(groups.find((g) => g.genus === 'Dacelo').name, 'Kookaburras');
  assert.ok(!groups.some((g) => g.genus === 'Dromaius'), 'single-species genus is not a group');
});

test('groups are searchable', () => {
  assert.ok(groupsMatching(groups, 'rosel').some((g) => g.genus === 'Platycercus'));
  assert.ok(groupsMatching(groups, 'flightless').some((g) => g.id === 'flightless'));
  assert.deepEqual(groupsMatching(groups, 'ro'), [], 'too short to suggest groups');
});
