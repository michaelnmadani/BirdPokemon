// Small DOM helpers. `h('div.card', {onclick}, child, ...)` builds elements.

export function h(spec, props = {}, ...children) {
  const [tag, ...classes] = spec.split('.');
  const el = document.createElement(tag || 'div');
  if (classes.length) el.className = classes.join(' ');
  if (props === null || typeof props !== 'object' || props instanceof Node || Array.isArray(props)) {
    children.unshift(props);
    props = {};
  }
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
    else if (key === 'style' && typeof value === 'object') Object.assign(el.style, value);
    else if (key === 'dataset') Object.assign(el.dataset, value);
    else if (key in el && typeof value !== 'string') el[key] = value;
    else el.setAttribute(key, value === true ? '' : value);
  }
  append(el, children);
  return el;
}

function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
}

/** Species/remote photo with a bird placeholder when missing or failing. */
export function speciesImage(url, alt = '', className = 'thumb') {
  const wrap = h(`div.${className}`, { role: 'img', 'aria-label': alt });
  if (url) {
    const img = h('img', { src: url, alt: '', loading: 'lazy', decoding: 'async', crossorigin: 'anonymous' });
    img.addEventListener('error', () => img.remove());
    wrap.append(img);
  }
  return wrap;
}

/** Thumbnail of a stored sighting photo (object URL resolved asynchronously). */
export function sightingImage(store, id, kind = 'thumb', className = 'thumb') {
  const wrap = h(`div.${className}`);
  store.photoURL(id, kind).then((url) => {
    if (url) wrap.append(h('img', { src: url, alt: '' }));
  });
  return wrap;
}

/** A sighting's own photo, or the species' field-guide picture if it was logged without one. */
export function sightingPicture(app, sighting, kind = 'thumb', className = 'thumb') {
  if (sighting.hasPhoto === false) {
    return speciesImage(app.catalog.picture(app.catalog.get(sighting.speciesCode)), sighting.speciesCommonName, className);
  }
  return sightingImage(app.store, sighting.id, kind, className);
}

export function colorDot(hex, label, size = 10) {
  return h('span.dot', { title: label, 'aria-label': label, style: { background: hex, width: `${size}px`, height: `${size}px` } });
}

let toastTimer;
export function toast(message) {
  let el = document.getElementById('toast');
  if (!el) {
    el = h('div', { id: 'toast', role: 'status', 'aria-live': 'polite' });
    document.body.append(el);
  }
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 3200);
}

/** Promise-based confirm using <dialog>. */
export function confirmDialog({ title, message, confirm = 'Delete', destructive = true }) {
  return new Promise((resolve) => {
    const dialog = h('dialog.sheet.confirm',
      h('h2', title),
      message ? h('p.muted', message) : null,
      h('div.row.end',
        h('button.btn', { type: 'button', onclick: () => dialog.close('cancel') }, 'Cancel'),
        h(`button.btn.${destructive ? 'danger' : 'primary'}`, { type: 'button', onclick: () => dialog.close('ok') }, confirm),
      ),
    );
    dialog.addEventListener('close', () => {
      resolve(dialog.returnValue === 'ok');
      dialog.remove();
    });
    document.body.append(dialog);
    dialog.showModal();
  });
}

export function formatDate(iso, withTime = true) {
  const date = iso instanceof Date ? iso : new Date(iso);
  return date.toLocaleString(undefined, withTime
    ? { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' }
    : { day: 'numeric', month: 'short', year: 'numeric' });
}

export function formatCoord(lat, lon, digits = 4) {
  return `${lat.toFixed(digits)}, ${lon.toFixed(digits)}`;
}

/** "‹ Back" that falls back to a tab when the page was opened directly. */
export function backButton(app, fallback, label = 'Back') {
  return h('button.back', {
    type: 'button',
    onclick: () => (history.length > 1 ? history.back() : app.navigate(fallback)),
  }, `‹ ${label}`);
}
