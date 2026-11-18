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
    this.art = new Map();          // species code -> painting (url + credits)
    this.pictureStyle = readStyle();
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
        for (const s of species) if (!this.byCode.has(s.ebirdCode)) this.byCode.set(s.ebirdCode, s);
      } catch (err) {
        this.issues.push(`${code}: couldn't load species list (${err.message})`);
      }
      await this.loadArt(code);
    }
    return this;
  }

  /** Watercolours made by scripts/artwork/watercolour.py, if this build has them. */
  async loadArt(region) {
    try {
      const resp = await fetch(`data/art_${region}.json`);
      if (!resp.ok) return;
      const manifest = await resp.json();
      for (const [code, entry] of Object.entries(manifest.species ?? {})) {
        if (entry?.file) this.art.set(code, { ...entry, url: `art/${region}/${entry.file}` });
      }
    } catch {
      // No paintings in this build — photos are used everywhere.
    }
  }

  get hasArt() {
    return this.art.size > 0;
  }

  setPictureStyle(style) {
    this.pictureStyle = style;
    try {
      localStorage.setItem('pictures', style);
    } catch {
      // Private mode etc. — just won't persist.
    }
  }

  /** The picture to show for a species: its watercolour (when chosen and available) or photo. */
  picture(species) {
    if (!species) return null;
    if (this.pictureStyle === 'watercolour') {
      const art = this.art.get(species.ebirdCode);
      if (art) return art.url;
    }
    return species.thumbnailURL;
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

function readStyle() {
  try {
    return localStorage.getItem('pictures') === 'photo' ? 'photo' : 'watercolour';
  } catch {
    return 'watercolour';
  }
}
