// Bird groups: curated ones from groups.json (flightless birds, parrots, …)
// plus one group per genus with two or more species ("Rosellas · Platycercus").
// Mirrors SpeciesGroups.swift on iOS.

/** "Black-Cockatoo" -> "Black-Cockatoos", "Finch" -> "Finches", "Goose" -> "Geese". */
export function plural(word) {
  if (/goose$/i.test(word)) return word.replace(/oose$/i, (m) => (m[0] === 'O' ? 'Eese' : 'eese'));
  if (/(s|x|ch|sh)$/i.test(word)) return `${word}es`;
  if (/[^aeiou]y$/i.test(word)) return `${word.slice(0, -1)}ies`;
  return `${word}s`;
}

/** Name a genus from its members' common names, e.g. Rosellas, or Egrets & Herons. */
export function genusLabel(commonNames) {
  const counts = new Map();
  for (const name of commonNames) {
    const last = name.replace(/\s*\(.*\)\s*$/, '').trim().split(/\s+/).pop();
    if (last) counts.set(last, (counts.get(last) ?? 0) + 1);
  }
  const ranked = [...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  if (!ranked.length) return 'Birds';
  const [[top, topCount], second] = ranked;
  // One name if it covers most of the genus (Fantails); otherwise the top two (Crows & Ravens).
  if (!second || topCount >= commonNames.length * 0.75) return plural(top);
  return `${plural(top)} & ${plural(second[0])}`;
}

export function genusOf(species) {
  return species.scientificName.split(/\s+/)[0] ?? '';
}

function inDefinition(def, s) {
  if (def.species?.includes(s.ebirdCode)) return true;
  if (def.excludeFamilies?.includes(s.family)) return false;
  return Boolean(def.families?.includes(s.family) || def.orders?.includes(s.order));
}

/**
 * -> { groups: [{ id, name, emoji, kind: 'group'|'genus', genus?, species: [] }],
 *      byCode: Map<code, group[]> }
 * Every species ends up in at least one curated group ("Other birds" catches the rest).
 */
export function buildGroups(definitions, speciesList) {
  const groups = [];
  for (const def of definitions) {
    const members = speciesList.filter((s) => inDefinition(def, s));
    if (members.length) groups.push({ id: def.id, name: def.name, emoji: def.emoji ?? '🐦', kind: 'group', species: members });
  }
  const grouped = new Set(groups.flatMap((g) => g.species.map((s) => s.ebirdCode)));
  const others = speciesList.filter((s) => !grouped.has(s.ebirdCode));
  if (others.length) groups.push({ id: 'other', name: 'Other birds', emoji: '🐤', kind: 'group', species: others });

  const byGenus = new Map();
  for (const s of speciesList) {
    const genus = genusOf(s);
    if (!byGenus.has(genus)) byGenus.set(genus, []);
    byGenus.get(genus).push(s);
  }
  const genera = [...byGenus]
    .filter(([, members]) => members.length >= 2)
    .map(([genus, members]) => ({
      id: `genus-${genus}`,
      name: genusLabel(members.map((s) => s.commonName)),
      emoji: '🔗',
      kind: 'genus',
      genus,
      species: members,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
  groups.push(...genera);

  const byCode = new Map();
  for (const g of groups) {
    for (const s of g.species) {
      if (!byCode.has(s.ebirdCode)) byCode.set(s.ebirdCode, []);
      byCode.get(s.ebirdCode).push(g);
    }
  }
  return { groups, byCode };
}

/** Text a search should match for a group (its name, and genus if any). */
export function groupSearchText(group) {
  return `${group.name} ${group.genus ?? ''}`.toLowerCase();
}

export function groupsMatching(groups, query, limit = 6) {
  const needle = query.trim().toLowerCase();
  if (needle.length < 3) return [];
  return groups.filter((g) => groupSearchText(g).includes(needle)).slice(0, limit);
}
