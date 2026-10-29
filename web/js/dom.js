// Small DOM helpers. Text is always set as text, never as HTML, so note content can't inject markup.

const PROPS = new Set(['value', 'checked', 'disabled', 'selected', 'indeterminate']);

export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'text') el.textContent = value;
    else if (key === 'style' && typeof value === 'object') Object.assign(el.style, value);
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2).toLowerCase(), value);
    else if (PROPS.has(key)) el[key] = value;
    else el.setAttribute(key, value === true ? '' : String(value));
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return el;
}

export const $ = (selector, root = document) => root.querySelector(selector);

export function clear(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

/** A short message. `action` adds a button, for example { label: 'Undo', onClick }. */
export function toast(message, ms = 4000, action = null) {
  let host = document.getElementById('toasts');
  if (!host) {
    host = h('div', { id: 'toasts', 'aria-live': 'polite' });
    document.body.append(host);
  }
  const el = h('div', { class: 'toast' }, h('span', { text: message }));
  if (action) {
    el.append(h('button', {
      class: 'toast-action', text: action.label,
      onClick: () => {
        el.remove();
        action.onClick();
      },
    }));
  }
  host.append(el);
  setTimeout(() => el.remove(), ms);
}

/** A small pop-up menu under `anchor`. Items: { label, onClick, danger?, disabled? } or { divider: true }. */
export function popMenu(anchor, items) {
  document.querySelectorAll('.menu').forEach((m) => m.remove());
  const rect = anchor.getBoundingClientRect();
  const menu = h('div', { class: 'menu', role: 'menu' });
  for (const item of items) {
    if (item.divider) {
      menu.append(h('hr'));
      continue;
    }
    menu.append(
      h('button', {
        class: item.danger ? 'danger' : '',
        role: 'menuitem',
        disabled: item.disabled,
        text: item.label,
        onClick: () => {
          close();
          item.onClick?.();
        },
      }),
    );
  }
  document.body.append(menu);
  const left = Math.min(rect.left, window.innerWidth - menu.offsetWidth - 8);
  menu.style.left = `${Math.max(8, left)}px`;
  menu.style.top = `${Math.min(rect.bottom + 4, window.innerHeight - menu.offsetHeight - 8)}px`;

  function close() {
    menu.remove();
    document.removeEventListener('pointerdown', outside, true);
    document.removeEventListener('keydown', onKey, true);
  }
  function outside(e) {
    if (!menu.contains(e.target)) close();
  }
  function onKey(e) {
    if (e.key === 'Escape') close();
  }
  setTimeout(() => {
    document.addEventListener('pointerdown', outside, true);
    document.addEventListener('keydown', onKey, true);
  });
  return close;
}

/** A modal dialog. `build(close)` returns the content. */
export function modal(title, build, { wide = false } = {}) {
  const overlay = h('div', { class: 'overlay' });
  const close = () => overlay.remove();
  const box = h(
    'div',
    { class: `modal${wide ? ' wide' : ''}`, role: 'dialog', 'aria-modal': 'true', 'aria-label': title },
    h('div', { class: 'modal-head' }, h('h2', { text: title }), h('button', { class: 'icon', 'aria-label': 'Close', text: '×', onClick: close })),
    build(close),
  );
  overlay.append(box);
  overlay.addEventListener('pointerdown', (e) => {
    if (e.target === overlay) close();
  });
  document.body.append(overlay);
  return close;
}

export function download(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = h('a', { href: url, download: filename });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

export const formatBytes = (n) => {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(2)} GB`;
};

export const safeFilename = (s) => (String(s).replace(/[\\/:*?"<>|]+/g, '-').trim() || 'Note').slice(0, 80);
