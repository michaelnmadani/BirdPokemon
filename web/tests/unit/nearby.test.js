import { test } from 'node:test';
import assert from 'node:assert/strict';
import { daysAgo, distanceKm, parseEbirdDate, sightingsWithin, summarizeNearby } from '../../src/js/nearby.js';

const sydney = { lat: -33.8688, lon: 151.2093 };

test('distance between Sydney and Brisbane is about 730 km', () => {
  const km = distanceKm(sydney, { lat: -27.4698, lon: 153.0251 });
  assert.ok(km > 720 && km < 740, String(km));
  assert.equal(distanceKm(sydney, sydney), 0);
});

test('sightingsWithin keeps only located sightings inside the radius', () => {
  const sightings = [
    { id: 'near', latitude: -33.87, longitude: 151.21 },
    { id: 'edge', latitude: -33.9118, longitude: 151.2093 },   // ~4.8 km south
    { id: 'far', latitude: -33.95, longitude: 151.2093 },      // ~9 km south
    { id: 'nowhere', latitude: null, longitude: null },
  ];
  assert.deepEqual(sightingsWithin(sightings, sydney, 5).map((s) => s.id), ['near', 'edge']);
});

test('summarizeNearby merges your sightings with eBird reports per species', () => {
  const lookup = (code) => (code === 'galah' ? { ebirdCode: 'galah' } : null);
  const result = summarizeNearby({
    center: sydney,
    lookup,
    mine: [
      { speciesCode: 'galah', speciesCommonName: 'Galah', latitude: -33.87, longitude: 151.21, capturedAt: '2026-10-01T00:00:00Z' },
      { speciesCode: 'galah', speciesCommonName: 'Galah', latitude: -33.86, longitude: 151.2, capturedAt: '2026-09-01T00:00:00Z' },
    ],
    reports: [
      { speciesCode: 'galah', comName: 'Galah', obsDt: '2026-10-05 10:00', lat: -33.87, lng: 151.2 },
      { speciesCode: 'other1', comName: 'Other', obsDt: '2026-10-06', lat: -33.87, lng: 151.2 },
      { speciesCode: 'far1', comName: 'Far', obsDt: '2026-10-06', lat: -30, lng: 150 },
    ],
  });
  assert.deepEqual(result.map((e) => e.code), ['other1', 'galah']);
  const galah = result.find((e) => e.code === 'galah');
  assert.equal(galah.mine.length, 2);
  assert.equal(galah.report.obsDt, '2026-10-05 10:00');
  assert.ok(galah.species);
  assert.equal(result.find((e) => e.code === 'other1').species, null);
});

test('eBird dates and relative days', () => {
  const d = parseEbirdDate('2026-10-18 08:15');
  assert.equal(d.getHours(), 8);
  assert.equal(parseEbirdDate('2026-10-18').getDate(), 18);
  const now = new Date(2026, 9, 20, 12);
  assert.equal(daysAgo(new Date(2026, 9, 20, 6), now), 'today');
  assert.equal(daysAgo(new Date(2026, 9, 19, 23), now), 'yesterday');
  assert.equal(daysAgo(new Date(2026, 9, 17), now), '3 days ago');
});
