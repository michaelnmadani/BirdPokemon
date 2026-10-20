// Loads the bundled species lists (the same JSON the iOS app ships).
import { buildGroups } from './groups.js';
import { normalizeSpecies } from './model.js';

export class Catalog {
  constructor() {
    this.byRegion = new Map();
    this.byCode = new Map();
    this.issues = [];
    this.groupDefinitions = [];
    this.groupCache = new Map();
  }

  async load() {
    const regions = await (await fetch('data/regions.json')).json();
    try {
      this.groupDefinitions = await (await fetch('data/groups.json')).json();
    } catch (err) {
      this.issues.push(`Bird groups unavailable (${err.message})`);
    }
    for (const code of regions) {
      try {
        const raw = await (await fetch(`data/taxonomy_${code}.json`)).json();
        const species = raw.map(normalizeSpecies).filter(Boolean);
        if (species.length < raw.length) this.issues.push(`${code}: skipped ${raw.length - species.length} unreadable species`);
        this.byRegion.set(code, species);
        // Group names are searchable: "parrot" finds Galahs, "rosella" every rosella.
        const { byCode } = this.groupsFor(code);
        for (const s of species) {
          s.groupText = (byCode.get(s.ebirdCode) ?? []).map((g) => `${g.name} ${g.genus ?? ''}`).join(' ');
        }
        for (const s of species) if (!this.byCode.has(s.ebirdCode)) this.byCode.set(s.ebirdCode, s);
      } catch (err) {
        this.issues.push(`${code}: couldn't load species list (${err.message})`);
      }
    }
    return this;
  }

  get regions() {
    return [...this.byRegion.keys()].filter((code) => this.byRegion.get(code).length > 0);
  }

  species(region) {
    return this.byRegion.get(region) ?? [];
  }

  get(code) {
    return this.byCode.get(code) ?? null;
  }

  /** { groups, byCode } for a region, computed once. */
  groupsFor(region) {
    if (!this.groupCache.has(region)) {
      this.groupCache.set(region, buildGroups(this.groupDefinitions, this.byRegion.get(region) ?? []));
    }
    return this.groupCache.get(region);
  }

  group(region, id) {
    return this.groupsFor(region).groups.find((g) => g.id === id) ?? null;
  }
}
