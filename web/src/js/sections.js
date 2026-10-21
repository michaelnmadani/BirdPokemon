// Collection grid sections: group species by bird group, family, size or
// colour. Pure functions so they run under `node --test`. Mirrors
// CollectionSections.swift on iOS.
import { COLORS, SIZES } from './model.js';

export const GROUPINGS = [
  { id: 'none', label: 'None' },
  { id: 'group', label: 'Bird group' },
  { id: 'family', label: 'Family' },
  { id: 'size', label: 'Size' },
  { id: 'colour', label: 'Colour' },
];

export const GRID_SIZES = [
  { id: 'small', label: 'S', min: 76 },
  { id: 'medium', label: 'M', min: 104 },
  { id: 'large', label: 'L', min: 150 },
];

const COLOUR_NAMES = { gray: 'Grey' };
const capitalise = (s) => s[0].toUpperCase() + s.slice(1);

/**
 * -> [{ id, title, emoji?, swatch?, species: [] }] in a natural order, empty
 * sections dropped. `groups` is the catalog's curated groups (definition
 * order); each species goes in the first one it belongs to, so it appears once.
 */
export function sections(species, by, groups = []) {
  if (by === 'none') return [{ id: 'all', title: null, species }];

  const buckets = new Map();
  const add = (key, s) => {
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(s);
  };

  if (by === 'group') {
    const curated = groups.filter((g) => g.kind === 'group');
    const first = new Map();
    for (const g of curated) {
      for (const s of g.species) if (!first.has(s.ebirdCode)) first.set(s.ebirdCode, g.id);
    }
    for (const s of species) add(first.get(s.ebirdCode) ?? 'other', s);
    const meta = new Map(curated.map((g) => [g.id, g]));
    if (!meta.has('other')) meta.set('other', { id: 'other', name: 'Other birds', emoji: '🐤' });
    return [...meta.values()]
      .filter((g) => buckets.has(g.id))
      .map((g) => ({ id: g.id, title: g.name, emoji: g.emoji, species: buckets.get(g.id) }));
  }

  if (by === 'family') {
    // Families keep the taxonomic order the species list is already in.
    for (const s of species) add(s.familyDisplayName, s);
    return [...buckets].map(([name, list]) => ({
      id: name, title: name, subtitle: list[0].family !== name ? list[0].family : null, species: list,
    }));
  }

  if (by === 'size') {
    for (const s of species) add(s.sizeCategory, s);
    return SIZES.filter((z) => buckets.has(z.id))
      .map((z) => ({ id: z.id, title: `${z.label} · ${z.length}`, species: buckets.get(z.id) }));
  }

  if (by === 'colour') {
    // A bird's first listed colour is its main one.
    for (const s of species) add(s.primaryColors[0] ?? 'unknown', s);
    const order = [...Object.keys(COLORS), 'unknown'];
    return order.filter((c) => buckets.has(c)).map((c) => ({
      id: c,
      title: c === 'unknown' ? 'Colour not recorded' : (COLOUR_NAMES[c] ?? capitalise(c)),
      swatch: COLORS[c] ?? null,
      species: buckets.get(c),
    }));
  }

  throw new Error(`Unknown grouping: ${by}`);
}
