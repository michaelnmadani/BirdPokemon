// Loads the bundled species lists (the same JSON the iOS app ships).
import { normalizeSpecies } from './model.js';

export class Catalog {
  constructor() {
    this.byRegion = new Map();
    this.byCode = new Map();
    this.issues = [];
  }

  async load() {
    const regions = await (await fetch('data/regions.json')).json();
    for (const code of regions) {
      try {
        const raw = await (await fetch(`data/taxonomy_${code}.json`)).json();
        const species = raw.map(normalizeSpecies).filter(Boolean);
        if (species.length < raw.length) this.issues.push(`${code}: skipped ${raw.length - species.length} unreadable species`);
        this.byRegion.set(code, species);
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
}
