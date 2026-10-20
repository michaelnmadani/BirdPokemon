// Search field + filter button + filter sheet, shared by Collection and Field Guide.
import { COLORS, SIZES, activeFilterCount, emptyCriteria, familyOptions } from '../model.js';
import { h } from '../ui.js';

/**
 * Returns { node, update(count) }. `onChange` runs whenever search or
 * filters change; the caller re-renders its results.
 */
export function filterBar(criteria, allSpecies, onChange, placeholder = 'Search species') {
  const count = h('span.muted.small');
  const badge = h('span.badge');
  const clear = h('button.link', { type: 'button', onclick: () => {
    Object.assign(criteria, { ...emptyCriteria(), search: criteria.search });
    sync();
    onChange();
  } }, 'Clear');

  const search = h('input.search', {
    type: 'search', placeholder, value: criteria.search, 'aria-label': placeholder,
    autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false',
  });
  search.addEventListener('input', () => {
    criteria.search = search.value;
    onChange();
  });

  const button = h('button.btn.small', { type: 'button', onclick: () => openSheet(criteria, allSpecies, () => { sync(); onChange(); }) },
    'Filters', badge);

  function sync() {
    const n = activeFilterCount(criteria);
    badge.textContent = n ? String(n) : '';
    badge.hidden = !n;
    clear.hidden = !n;
  }
  sync();

  return {
    node: h('div.filterbar', search, h('div.row', button, clear, h('span.spacer'), count)),
    update(n) {
      count.textContent = `${n} species`;
    },
  };
}

function toggle(set, value, on) {
  if (on) set.add(value);
  else set.delete(value);
}

function openSheet(criteria, allSpecies, onChange) {
  const sizeRows = SIZES.map((size) => {
    const input = h('input', { type: 'checkbox', checked: criteria.sizes.has(size.id) });
    input.addEventListener('change', () => { toggle(criteria.sizes, size.id, input.checked); onChange(); });
    return h('label.check', input, h('span', size.label), h('span.muted.small', size.length));
  });

  const chips = Object.entries(COLORS).map(([name, hex]) => {
    const chip = h('button.chip', { type: 'button', 'aria-pressed': String(criteria.colors.has(name)) },
      h('span.dot.big', { style: { background: hex } }), name[0].toUpperCase() + name.slice(1));
    chip.addEventListener('click', () => {
      const on = !criteria.colors.has(name);
      toggle(criteria.colors, name, on);
      chip.setAttribute('aria-pressed', String(on));
      onChange();
    });
    return chip;
  });

  const familyRows = familyOptions(allSpecies).map(({ family, label }) => {
    const input = h('input', { type: 'checkbox', checked: criteria.families.has(family) });
    input.addEventListener('change', () => { toggle(criteria.families, family, input.checked); onChange(); });
    return h('label.check', input, h('span', label));
  });

  const dialog = h('dialog.sheet',
    h('div.sheet-head', h('h2', 'Filters'), h('button.btn.primary.small', { type: 'button', onclick: () => dialog.close() }, 'Done')),
    h('h3', 'Size'), h('div.list', sizeRows),
    h('h3', 'Main colours'), h('div.chips', chips),
    h('h3', 'Family'), h('div.list.scroll', familyRows),
  );
  dialog.addEventListener('close', () => dialog.remove());
  document.body.append(dialog);
  dialog.showModal();
}
