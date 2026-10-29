// Inkwell web portal: sign-in, account creation, recovery, library and settings.

import { h, $, clear, toast, popMenu, modal, formatBytes } from './dom.js';
import { Api, ApiError } from './api.js';
import * as C from './crypto.js';
import { deviceVault, blobCache } from './idb.js';
import { Library } from './store.js';
import { Editor } from './editor.js';
import {
  TEMPLATES, CATEGORIES, drawTemplate, PAGE_W, PAGE_H, templateTitle,
  PAPER_PRESETS, WHITEBOARD_SIZES, PAPER_COLOURS, COVER_COLOURS, WHITEBOARD_BACKGROUNDS,
} from './templates.js';
import { drawPaper, drawInk, pageSpec } from './render.js';

const root = $('#app');
const app = { api: null, user: null, master: null, lib: null, editor: null, view: 'auth', folder: 'all', search: '', remember: false };

// ---------- settings kept in this browser ----------

const local = {
  get(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set(key, value) {
    try {
      value === null ? localStorage.removeItem(key) : localStorage.setItem(key, value);
    } catch {
      /* storage unavailable */
    }
  },
};

const configuredApi = () => (window.INKWELL_API || '').trim();
const apiBase = () => (local.get('inkwell.api') || configuredApi()).trim();

function saveSession(remember) {
  if (!remember) return local.set('inkwell.session', null);
  local.set(
    'inkwell.session',
    JSON.stringify({ token: app.api.token, api: app.api.base, user: app.user, expires: app.expires }),
  );
}

function readSession() {
  try {
    return JSON.parse(local.get('inkwell.session') || 'null');
  } catch {
    return null;
  }
}

// ---------- helpers ----------

const friendly = (err) => (err instanceof Error ? err.message : String(err));

function busy(button, label, fn) {
  const original = button.textContent;
  button.disabled = true;
  button.textContent = label;
  return fn().finally(() => {
    button.disabled = false;
    button.textContent = original;
  });
}

async function fetchEnvelope(api) {
  try {
    const { bytes, version } = await api.getBlob('envelope');
    return { envelope: C.parseJsonBytes(bytes), version };
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}

const putEnvelope = (api, envelope, version) => api.putBlob('envelope', 'envelope', C.jsonBytes(envelope), version ?? null);

const newSalt = () => C.toB64Url(C.randomBytes(16));

function checkPassword(password, confirm) {
  if (password.length < 10) throw new Error('Use a password of at least 10 characters. A few random words works well.');
  if (confirm !== undefined && password !== confirm) throw new Error('The two passwords do not match.');
}

// ---------- screens ----------

function setView(name) {
  app.view = name;
  document.body.dataset.view = name;
  // Dialogs and menus belong to the screen that opened them.
  document.querySelectorAll('.overlay, .menu').forEach((el) => el.remove());
}

function loading(message) {
  setView('loading');
  clear(root).append(h('div', { class: 'center-card' }, h('div', { class: 'spinner', 'aria-hidden': 'true' }), h('p', { text: message })));
}

function showAuth(message = '', tab = 'signin') {
  setView('auth');
  const errorBox = h('p', { class: 'error', role: 'alert', text: message });
  const serverInput = h('input', { type: 'url', placeholder: 'https://inkwell-sync.example.workers.dev', value: apiBase(), autocomplete: 'off' });
  const serverField = h(
    'details',
    { class: 'server', open: !apiBase() },
    h('summary', { text: 'Server address' }),
    h('label', { class: 'field' }, 'Where your notes are stored', serverInput),
  );

  const email = h('input', { type: 'email', required: true, autocomplete: 'username', placeholder: 'you@example.com' });
  const field = (text, input) => h('label', { class: 'field' }, text, input);
  const password = (autocomplete) => h('input', { type: 'password', required: true, autocomplete, minlength: '1' });
  const rememberBox = h('input', { type: 'checkbox', checked: true });
  const remember = h('label', { class: 'check' }, rememberBox, 'Keep me signed in on this device');

  const withApi = () => {
    const base = serverInput.value.trim();
    if (!/^https?:\/\//i.test(base)) throw new Error('Enter the server address first (open "Server address").');
    local.set('inkwell.api', base);
    return new Api(base);
  };

  const submit = (form, label, fn) =>
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      errorBox.textContent = '';
      const button = $('button[type=submit]', form);
      busy(button, label, async () => {
        try {
          await fn();
        } catch (err) {
          errorBox.textContent = friendly(err);
        }
      });
    });

  // ----- sign in -----
  const pwIn = password('current-password');
  const signInForm = h('form', { class: 'stack' }, field('Email', email), field('Password', pwIn), remember,
    h('button', { class: 'btn primary wide', type: 'submit', text: 'Sign in' }));
  submit(signInForm, 'Signing in…', async () => {
    const api = withApi();
    const em = email.value.trim().toLowerCase();
    const pre = await api.prelogin(em);
    const { encKey, loginKey } = await C.stretch(pwIn.value, pre.salt, pre.iterations);
    const session = await api.login(em, loginKey);
    api.token = session.token;
    let master;
    const found = await fetchEnvelope(api);
    if (found) {
      master = await C.unwrapWithPassword(found.envelope, encKey);
    } else {
      // An account with no key yet (for example the very first sign-in after an interrupted sign-up).
      const made = await C.createEnvelope(encKey);
      await putEnvelope(api, made.envelope, null);
      master = made.master;
      return showRecovery(made.recoveryKey, () => start(api, session, master, rememberBox.checked));
    }
    await start(api, session, master, rememberBox.checked);
  });

  // ----- create account -----
  const inviteIn = h('input', { type: 'text', required: true, autocomplete: 'off', placeholder: 'ABCD-EFGH-JKLM-NPQR', spellcheck: 'false' });
  const regEmail = h('input', { type: 'email', required: true, autocomplete: 'username' });
  const regPw = password('new-password');
  const regPw2 = password('new-password');
  const registerForm = h('form', { class: 'stack' },
    h('p', { class: 'hint', text: 'You need an invite code from the person who runs this service.' }),
    field('Invite code', inviteIn), field('Email', regEmail),
    field('Choose a password', regPw), field('Type it again', regPw2),
    h('p', { class: 'hint', text: 'This password also locks your notes. Nobody else can reset it, but you will get a recovery key as a backup.' }),
    h('button', { class: 'btn primary wide', type: 'submit', text: 'Create account' }));
  submit(registerForm, 'Creating…', async () => {
    checkPassword(regPw.value, regPw2.value);
    const api = withApi();
    const em = regEmail.value.trim().toLowerCase();
    const pre = await api.prelogin(em);
    const salt = newSalt();
    const { encKey, loginKey } = await C.stretch(regPw.value, salt, pre.iterations);
    const made = await C.createEnvelope(encKey);
    const session = await api.register(inviteIn.value.trim(), em, salt, loginKey);
    api.token = session.token;
    await putEnvelope(api, made.envelope, null);
    showRecovery(made.recoveryKey, () => start(api, session, made.master, true));
  });

  // ----- forgot password -----
  const fEmail = h('input', { type: 'email', required: true, autocomplete: 'username' });
  const fCode = h('input', { type: 'text', required: true, autocomplete: 'off', placeholder: 'Reset code from your administrator', spellcheck: 'false' });
  const fRecovery = h('input', { type: 'text', required: true, autocomplete: 'off', placeholder: 'ABCD-EFGH-…', spellcheck: 'false' });
  const fPw = password('new-password');
  const fPw2 = password('new-password');
  const forgotForm = h('form', { class: 'stack' },
    h('p', { class: 'hint', text: 'Ask the administrator for a reset code. You also need the recovery key you saved when you made your account.' }),
    field('Email', fEmail), field('Reset code', fCode), field('Recovery key', fRecovery),
    field('New password', fPw), field('Type it again', fPw2),
    h('button', { class: 'btn primary wide', type: 'submit', text: 'Reset password' }));
  submit(forgotForm, 'Resetting…', async () => {
    checkPassword(fPw.value, fPw2.value);
    C.decodeRecoveryKey(fRecovery.value); // checks the format before the code is used up
    const api = withApi();
    const em = fEmail.value.trim().toLowerCase();
    const pre = await api.prelogin(em);
    const salt = newSalt();
    const { encKey, loginKey } = await C.stretch(fPw.value, salt, pre.iterations);
    const session = await api.reset(fCode.value.trim(), em, salt, loginKey);
    api.token = session.token;
    const found = await fetchEnvelope(api);
    if (!found) throw new Error('No encryption key was found for this account.');
    await finishReset(api, session, found, encKey, fRecovery.value);
  });

  const panels = { signin: signInForm, register: registerForm, forgot: forgotForm };
  const tabs = h('div', { class: 'tabs', role: 'tablist' });
  const show = (name) => {
    errorBox.textContent = '';
    for (const [key, panel] of Object.entries(panels)) panel.hidden = key !== name;
    for (const btn of tabs.children) btn.setAttribute('aria-selected', String(btn.dataset.tab === name));
  };
  for (const [key, text] of [['signin', 'Sign in'], ['register', 'Create account'], ['forgot', 'Forgot password']]) {
    tabs.append(h('button', { type: 'button', role: 'tab', 'data-tab': key, text, onClick: () => show(key) }));
  }

  clear(root).append(
    h('main', { class: 'auth' },
      h('div', { class: 'auth-card' },
        h('h1', { class: 'brand', text: 'Inkwell' }),
        h('p', { class: 'tagline', text: 'Your notes, encrypted, on every device.' }),
        tabs, errorBox, signInForm, registerForm, forgotForm, serverField)),
  );
  show(tab);
}

/** After a reset code is accepted, the recovery key unlocks the notes. A wrong key can be retried. */
async function finishReset(api, session, found, encKey, recoveryText, errorBox) {
  try {
    const master = await C.unwrapWithRecovery(found.envelope, recoveryText);
    const envelope = await C.rewrapPassword(found.envelope, master, encKey);
    await putEnvelope(api, envelope, found.version);
    toast('Password changed.');
    await start(api, session, master, true);
  } catch (err) {
    // The reset code is already used, so ask for the recovery key again rather than starting over.
    setView('auth');
    const input = h('input', { type: 'text', required: true, placeholder: 'ABCD-EFGH-…', spellcheck: 'false', autocomplete: 'off' });
    const error = h('p', { class: 'error', role: 'alert', text: friendly(err) });
    const form = h('form', { class: 'stack' }, h('label', { class: 'field' }, 'Recovery key', input), error,
      h('button', { class: 'btn primary wide', type: 'submit', text: 'Try again' }));
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      busy($('button', form), 'Checking…', () => finishReset(api, session, found, encKey, input.value));
    });
    clear(root).append(h('main', { class: 'auth' }, h('div', { class: 'auth-card' },
      h('h1', { class: 'brand', text: 'Recovery key' }),
      h('p', { class: 'hint', text: 'Your new password is set, but that recovery key did not unlock your notes. Check it and try again.' }),
      form)));
  }
}

function showRecovery(key, next) {
  setView('auth');
  const ok = h('input', { type: 'checkbox' });
  const go = h('button', { class: 'btn primary wide', disabled: true, text: 'Continue' });
  ok.addEventListener('change', () => (go.disabled = !ok.checked));
  go.addEventListener('click', () => busy(go, 'Opening…', () => next().catch((e) => toast(friendly(e)))));
  clear(root).append(
    h('main', { class: 'auth' }, h('div', { class: 'auth-card' },
      h('h1', { class: 'brand', text: 'Save your recovery key' }),
      h('p', { text: 'If you ever forget your password, this key is the only way to get your notes back. Not even the administrator can recover them without it.' }),
      h('div', { class: 'recovery', 'aria-label': 'Recovery key', text: key }),
      h('div', { class: 'row-btns' },
        h('button', { class: 'btn', text: 'Copy', onClick: async () => { try { await navigator.clipboard.writeText(key); toast('Copied.'); } catch { toast('Copy failed. Select the text instead.'); } } }),
        h('button', { class: 'btn', text: 'Print', onClick: () => printKey(key) })),
      h('p', { class: 'hint', text: 'Write it down or print it and keep it somewhere safe, away from this device. Do not store it only in a note in this app.' }),
      h('label', { class: 'check' }, ok, 'I have saved my recovery key'),
      go)),
  );
}

function printKey(key) {
  const w = window.open('', '_blank', 'width=600,height=400');
  if (!w) return toast('Allow pop-ups to print, or copy the key instead.');
  w.document.title = 'Inkwell recovery key';
  const style = w.document.createElement('style');
  style.textContent = 'body{font:16px system-ui;padding:40px}code{display:block;font:22px/1.6 ui-monospace,monospace;margin:24px 0;word-break:break-all}';
  w.document.head.append(style);
  w.document.body.append(Object.assign(w.document.createElement('h1'), { textContent: 'Inkwell recovery key' }));
  w.document.body.append(Object.assign(w.document.createElement('code'), { textContent: key }));
  w.document.body.append(Object.assign(w.document.createElement('p'), { textContent: 'Keep this somewhere safe. Anyone with it and your account email can unlock your notes after a password reset.' }));
  w.print();
}

// ---------- starting and stopping ----------

async function start(api, session, master, remember) {
  app.api = api;
  app.user = session.user;
  app.expires = session.expires;
  app.master = master;
  app.remember = remember;
  if (remember) {
    await deviceVault.save(master);
    saveSession(true);
  } else {
    await deviceVault.clear();
    saveSession(false);
  }
  loading('Unlocking and syncing your notes…');
  app.lib = new Library(api, master);
  try {
    await app.lib.load();
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) return signOut('Your session has ended. Please sign in again.');
    return showLoadError(err);
  }
  app.lib.startPolling();
  app.lib.addEventListener('notes', () => app.view === 'library' && scheduleRender());
  app.lib.addEventListener('removed', (e) => {
    if (app.editor && app.editor.noteId === e.detail.id) {
      toast('This note was deleted on another device.');
      closeEditor();
    }
  });
  app.lib.addEventListener('signed-out', () => signOut('Your session has ended. Please sign in again.'));
  showLibrary();
}

function showLoadError(err) {
  setView('loading');
  clear(root).append(h('div', { class: 'center-card' }, h('p', { class: 'error', text: friendly(err) }),
    h('div', { class: 'row-btns' },
      h('button', { class: 'btn primary', text: 'Try again', onClick: () => start(app.api, { user: app.user, expires: app.expires }, app.master, app.remember) }),
      h('button', { class: 'btn', text: 'Sign out', onClick: () => signOut() }))));
}

async function signOut(message = '') {
  app.lib?.stopPolling();
  app.editor?.destroy();
  app.editor = null;
  try {
    await app.api?.logout();
  } catch {
    /* already ended */
  }
  await Promise.all([deviceVault.clear(), blobCache.clear()]);
  saveSession(false);
  Object.assign(app, { api: null, user: null, master: null, lib: null, folder: 'all', search: '' });
  showAuth(message);
}

// ---------- library ----------

let renderTimer = null;
function scheduleRender() {
  clearTimeout(renderTimer);
  renderTimer = setTimeout(() => app.view === 'library' && renderLibrary(), 80);
}

const relative = (ms) => {
  const days = Math.floor((Date.now() - ms) / 86400000);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days} days ago`;
  return new Date(ms).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: days > 300 ? 'numeric' : undefined });
};

function showLibrary() {
  setView('library');
  app.editor?.destroy();
  app.editor = null;
  const status = h('span', { class: 'sync-status', role: 'status' });
  const search = h('input', {
    type: 'search', placeholder: 'Search titles', 'aria-label': 'Search note titles', value: app.search,
    onInput: () => {
      app.search = search.value;
      renderLibrary();
    },
  });
  const updateStatus = () => {
    const { status: s, statusDetail } = app.lib;
    status.textContent = { synced: 'All changes saved', saving: 'Saving…', syncing: 'Syncing…', offline: `Offline${statusDetail ? `: ${statusDetail}` : ''}`, idle: '' }[s] ?? '';
    status.classList.toggle('bad', s === 'offline');
  };
  updateStatus();
  if (app.statusHandler) app.lib.removeEventListener('status', app.statusHandler);
  app.statusHandler = () => app.view === 'library' && updateStatus();
  app.lib.addEventListener('status', app.statusHandler);

  const newBtn = h('button', { class: 'btn primary', text: 'New ▾', 'aria-haspopup': 'menu' });
  newBtn.addEventListener('click', () =>
    popMenu(newBtn, [
      { label: 'New note', onClick: () => pickTemplate() },
      { label: 'New notebook…', onClick: () => setupNotebook() },
      { label: 'New whiteboard…', onClick: () => setupWhiteboard() },
    ]));

  clear(root).append(
    h('div', { class: 'library' },
      h('header', { class: 'lib-top' },
        h('h1', { class: 'brand', text: 'Inkwell' }), search, status,
        newBtn,
        h('button', { class: 'btn', text: 'Settings', onClick: () => showSettings() })),
      h('div', { class: 'lib-body' }, h('nav', { class: 'folders', 'aria-label': 'Folders' }), h('main', { class: 'notes' }))),
  );
  renderLibrary();
}

function renderLibrary() {
  const nav = $('.folders');
  const main = $('.notes');
  if (!nav || !main) return;
  const lib = app.lib;
  const all = lib.notes();

  // folders
  clear(nav);
  const folderBtn = (id, name, count, actions) =>
    h('div', { class: `folder${app.folder === id ? ' on' : ''}` },
      h('button', { class: 'folder-name', 'aria-current': String(app.folder === id), onClick: () => { app.folder = id; renderLibrary(); } },
        h('span', { text: name }), h('span', { class: 'count', text: String(count) })),
      actions || null);
  nav.append(folderBtn('all', 'All notes', all.length));
  for (const f of lib.folders) {
    const more = h('button', { class: 'icon', 'aria-label': `Folder options for ${f.name}`, text: '⋯' });
    more.addEventListener('click', () =>
      popMenu(more, [
        { label: 'Rename', onClick: () => { const n = prompt('Folder name', f.name); if (n && n.trim()) lib.renameFolder(f.id, n.trim()); } },
        { label: 'Delete folder', danger: true, onClick: () => {
          if (!confirm(`Delete the folder "${f.name}"? Its notes are kept and moved to All notes.`)) return;
          if (app.folder === f.id) app.folder = 'all';
          lib.deleteFolder(f.id);
        } },
      ]));
    nav.append(folderBtn(f.id, f.name, all.filter((n) => n.folderId === f.id).length, more));
  }
  nav.append(h('button', { class: 'btn small ghost', text: '+ New folder', onClick: () => { const n = prompt('Folder name'); if (n && n.trim()) lib.addFolder(n.trim()); } }));

  // notes
  const q = app.search.trim().toLowerCase();
  const shown = all
    .filter((n) => app.folder === 'all' || n.folderId === app.folder)
    .filter((n) => !q || n.title.toLowerCase().includes(q))
    .sort((a, b) => b.modified - a.modified);

  clear(main);
  const current = app.folder === 'all' ? 'All notes' : lib.folders.find((f) => f.id === app.folder)?.name || 'Notes';
  main.append(h('h2', { class: 'section', text: current }));
  if (!shown.length) {
    main.append(h('div', { class: 'empty' }, h('p', { text: q ? 'No notes match that search.' : 'No notes here yet.' }),
      q ? null : h('button', { class: 'btn primary', text: 'Create a note', onClick: () => pickTemplate() })));
    return;
  }
  const grid = h('div', { class: 'grid' });
  for (const note of shown) grid.append(noteCard(note));
  main.append(grid);
}

function noteCard(note) {
  const canvas = h('canvas', { class: 'thumb', 'aria-hidden': 'true' });
  queueThumb(canvas, note);
  const folder = app.lib.folders.find((f) => f.id === note.folderId)?.name;
  const kind = { notebook: 'Notebook · ', whiteboard: 'Whiteboard · ' }[note.kind] || '';
  const pw = note.pageWidth || PAGE_W;
  const ph = note.pageHeight || PAGE_H;
  const pages = note.kind === 'whiteboard' ? '' : ` · ${note.pages.length} page${note.pages.length === 1 ? '' : 's'}`;
  const open = h('button', { class: 'card-open', 'aria-label': `Open ${note.title}`, onClick: () => openEditor(note.id) },
    h('div', { class: 'thumb-wrap', style: { aspectRatio: `${pw} / ${ph}` } }, canvas,
      note.kind === 'notebook' && note.cover ? h('span', { class: 'spine', style: { background: note.cover } }) : null,
      note.kind && note.kind !== 'note' ? h('span', { class: 'badge', 'aria-hidden': 'true', text: note.kind === 'whiteboard' ? '▭' : '▤' }) : null),
    h('div', { class: 'card-title', text: note.title || 'Untitled note' }),
    h('div', { class: 'card-meta', text: `${folder ? `${folder} · ` : ''}${kind}${relative(note.modified)}${pages}` }));
  const more = h('button', { class: 'icon card-more', 'aria-label': `Options for ${note.title}`, text: '⋯' });
  more.addEventListener('click', () =>
    popMenu(more, [
      { label: 'Rename', onClick: () => { const n = prompt('Note title', note.title); if (n && n.trim()) { note.title = n.trim(); app.lib.touch(note.id); renderLibrary(); } } },
      ...app.lib.folders.map((f) => ({ label: `Move to ${f.name}`, disabled: note.folderId === f.id, onClick: () => app.lib.moveNote(note.id, f.id) })),
      { label: 'Move out of folder', disabled: !note.folderId, onClick: () => app.lib.moveNote(note.id, null) },
      { divider: true },
      { label: 'Duplicate', onClick: () => app.lib.duplicateNote(note.id) },
      { label: 'Delete', danger: true, onClick: () => { if (confirm(`Delete "${note.title}"? It is kept for 30 days in case you need it back.`)) app.lib.deleteNote(note.id); } },
    ]));
  return h('article', { class: 'card' }, open, more);
}

// Thumbnails are drawn one at a time so a big library doesn't freeze the page.
const thumbQueue = [];
let thumbRunning = false;
function queueThumb(canvas, note) {
  thumbQueue.push([canvas, note]);
  if (!thumbRunning) {
    thumbRunning = true;
    setTimeout(runThumbs, 0);
  }
}
function runThumbs() {
  const job = thumbQueue.shift();
  if (!job) {
    thumbRunning = false;
    return;
  }
  const [canvas, note] = job;
  if (canvas.isConnected) drawThumb(canvas, note);
  setTimeout(runThumbs, 0);
}

function drawThumb(canvas, note) {
  const spec = pageSpec(note, 0);
  const width = 240;
  const height = Math.max(1, Math.round((width * spec.h) / spec.w));
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = width * dpr;
  canvas.height = height * dpr;
  const page = note.pages[0];
  const ctx = canvas.getContext('2d');
  const k = (width * dpr) / spec.w;
  ctx.setTransform(k, 0, 0, k, 0, 0);
  ctx.clearRect(0, 0, spec.w, spec.h);
  drawPaper(ctx, page, spec, app.lib.images);
  drawInk(ctx, page);
  // Pictures arrive asynchronously; redraw once when they have loaded.
  const pending = [page.background, ...(page.images || []).map((i) => i.file)].filter((id) => id && !app.lib.images.has(id));
  if (pending.length) {
    Promise.allSettled(pending.map((id) => app.lib.loadImage(id))).then(() => canvas.isConnected && drawThumb(canvas, note));
  }
}

// ---------- templates ----------

function pickTemplate() {
  let chosen = 'ruled';
  let category = 'Basic';
  const grid = h('div', { class: 'tpl-grid' });
  const tabs = h('div', { class: 'tabs small', role: 'tablist' });
  const render = () => {
    clear(grid);
    clear(tabs);
    for (const c of CATEGORIES) tabs.append(h('button', { role: 'tab', 'aria-selected': String(c === category), text: c, onClick: () => { category = c; render(); } }));
    for (const t of TEMPLATES.filter((x) => x.category === category)) {
      const canvas = h('canvas', { width: 240, height: Math.round((240 * PAGE_H) / PAGE_W) });
      const ctx = canvas.getContext('2d');
      ctx.scale(240 / PAGE_W, 240 / PAGE_W);
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, PAGE_W, PAGE_H);
      drawTemplate(ctx, t.id);
      grid.append(h('button', { class: `tpl${chosen === t.id ? ' on' : ''}`, 'aria-pressed': String(chosen === t.id), onClick: () => { chosen = t.id; render(); } },
        h('div', { class: 'thumb-wrap' }, canvas), h('div', { class: 'card-title', text: t.title })));
    }
  };
  render();
  modal('Choose a template', (close) =>
    h('div', { class: 'stack' }, tabs, grid,
      h('div', { class: 'row-btns end' },
        h('button', { class: 'btn', text: 'Cancel', onClick: close }),
        h('button', { class: 'btn primary', text: 'Create note', onClick: () => {
          const folderId = app.folder !== 'all' ? app.folder : null;
          const note = app.lib.createNote({ template: chosen, folderId });
          close();
          openEditor(note.id);
        } }))),
  { wide: true });
}

// ---------- notebooks and whiteboards ----------

function swatchRow(items, current, onPick) {
  const row = h('div', { class: 'swatch-row', role: 'radiogroup' });
  const render = () => {
    clear(row);
    for (const [name, hex] of items) {
      row.append(h('button', {
        type: 'button', role: 'radio', class: `sw${hex === current ? ' on' : ''}`, style: { background: hex },
        title: name, 'aria-label': name, 'aria-checked': String(hex === current),
        onClick: () => { current = hex; onPick(hex); render(); },
      }));
    }
  };
  render();
  return row;
}

function segmented(options, current, onPick) {
  const row = h('div', { class: 'seg', role: 'radiogroup' });
  const render = () => {
    clear(row);
    for (const [id, label] of options) {
      row.append(h('button', {
        type: 'button', role: 'radio', 'aria-checked': String(id === current), class: id === current ? 'on' : '',
        text: label, onClick: () => { current = id; onPick(id); render(); },
      }));
    }
  };
  render();
  return row;
}

const field = (label, control, hint) =>
  h('div', { class: 'field' }, label, control, hint ? h('span', { class: 'hint', text: hint }) : null);

/** Draws one blank page of the chosen paper into a small canvas. */
function paintPreview(canvas, spec, maxW, maxH) {
  const k = Math.min(maxW / spec.w, maxH / spec.h);
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.max(1, Math.round(spec.w * k * dpr));
  canvas.height = Math.max(1, Math.round(spec.h * k * dpr));
  canvas.style.width = `${Math.round(spec.w * k)}px`;
  canvas.style.height = `${Math.round(spec.h * k)}px`;
  const ctx = canvas.getContext('2d');
  ctx.setTransform(k * dpr, 0, 0, k * dpr, 0, 0);
  drawPaper(ctx, {}, spec, new Map());
}

function setupNotebook() {
  const opt = { title: 'My notebook', cover: COVER_COLOURS[0][1], preset: 'a4', landscape: false, template: 'ruled', paper: '#FFFFFF', numbers: true, pages: 20 };
  const size = () => {
    const p = PAPER_PRESETS.find((x) => x.id === opt.preset) || PAPER_PRESETS[0];
    return opt.landscape ? { w: p.h, h: p.w } : { w: p.w, h: p.h };
  };
  const preview = h('canvas', { class: 'nb-preview', 'aria-hidden': 'true' });
  const coverBar = h('span', { class: 'spine', style: { background: opt.cover } });
  const redraw = () => {
    const { w, h: hh } = size();
    paintPreview(preview, { w, h: hh, template: opt.template, paper: opt.paper, whiteboard: false, numbers: opt.numbers, number: 1 }, 190, 230);
    coverBar.style.background = opt.cover;
  };

  const strip = h('div', { class: 'tpl-strip', role: 'radiogroup', 'aria-label': 'Paper style' });
  const renderStrip = () => {
    clear(strip);
    for (const t of TEMPLATES) {
      const c = h('canvas', { width: 84, height: Math.round((84 * PAGE_H) / PAGE_W) });
      const ctx = c.getContext('2d');
      ctx.scale(84 / PAGE_W, 84 / PAGE_W);
      ctx.fillStyle = opt.paper;
      ctx.fillRect(0, 0, PAGE_W, PAGE_H);
      drawTemplate(ctx, t.id);
      strip.append(h('button', { type: 'button', role: 'radio', 'aria-checked': String(opt.template === t.id), class: `tpl-mini${opt.template === t.id ? ' on' : ''}`, onClick: () => { opt.template = t.id; renderStrip(); redraw(); } },
        c, h('span', { text: t.title })));
    }
  };

  const titleInput = h('input', { type: 'text', value: opt.title, maxlength: '80', onInput: () => { opt.title = titleInput.value; } });
  const sizeSelect = h('select', { onChange: () => { opt.preset = sizeSelect.value; redraw(); } },
    PAPER_PRESETS.map((p) => h('option', { value: p.id, text: `${p.title}  ·  ${p.detail}`, selected: p.id === opt.preset })));
  const pagesSelect = h('select', { onChange: () => { opt.pages = Number(pagesSelect.value); } },
    [1, 5, 10, 20, 50, 100, 200].map((n) => h('option', { value: String(n), text: String(n), selected: n === opt.pages })));
  const numbersBox = h('input', { type: 'checkbox', checked: opt.numbers, onChange: () => { opt.numbers = numbersBox.checked; redraw(); } });

  renderStrip();
  redraw();
  modal('New notebook', (close) =>
    h('div', { class: 'setup' },
      h('div', { class: 'setup-form stack' },
        field('Name', titleInput),
        field('Cover colour', swatchRow(COVER_COLOURS, opt.cover, (hex) => { opt.cover = hex; redraw(); })),
        field('Paper size', sizeSelect),
        field('Orientation', segmented([['p', 'Portrait'], ['l', 'Landscape']], 'p', (v) => { opt.landscape = v === 'l'; redraw(); })),
        field('Paper style', strip),
        field('Paper colour', swatchRow(PAPER_COLOURS, opt.paper, (hex) => { opt.paper = hex; renderStrip(); redraw(); })),
        h('label', { class: 'check' }, numbersBox, 'Page numbers'),
        field('Number of pages', pagesSelect, 'You can add, remove and reorder pages whenever you like.'),
        h('div', { class: 'row-btns end' },
          h('button', { class: 'btn', text: 'Cancel', onClick: close }),
          h('button', { class: 'btn primary', text: 'Create notebook', onClick: () => {
            const { w, h: hh } = size();
            const note = app.lib.createNote({
              title: opt.title.trim() || 'Notebook', template: opt.template, folderId: app.folder !== 'all' ? app.folder : null,
              kind: 'notebook', width: w, height: hh, cover: opt.cover, paper: opt.paper, pageNumbers: opt.numbers, pageCount: opt.pages,
            });
            close();
            openEditor(note.id);
          } }))),
      h('div', { class: 'setup-preview' }, h('div', { class: 'nb-wrap' }, preview, coverBar))),
  { wide: true });
}

function setupWhiteboard() {
  const opt = { title: 'Whiteboard', size: 'medium', background: 'blank', paper: '#FFFFFF' };
  const preview = h('canvas', { class: 'nb-preview', 'aria-hidden': 'true' });
  const redraw = () => {
    const s = WHITEBOARD_SIZES.find((x) => x.id === opt.size) || WHITEBOARD_SIZES[1];
    paintPreview(preview, { w: s.w, h: s.h, template: opt.background, paper: opt.paper, whiteboard: true, numbers: false, number: 1 }, 260, 190);
  };
  const sizeHint = h('span', { class: 'hint' });
  const hint = () => {
    const s = WHITEBOARD_SIZES.find((x) => x.id === opt.size);
    sizeHint.textContent = `${s.w} × ${s.h} points. A whiteboard is one big page. Zoom in and scroll to move around.`;
  };
  const titleInput = h('input', { type: 'text', value: opt.title, maxlength: '80', onInput: () => { opt.title = titleInput.value; } });
  hint();
  redraw();
  modal('New whiteboard', (close) =>
    h('div', { class: 'setup' },
      h('div', { class: 'setup-form stack' },
        field('Name', titleInput),
        h('div', { class: 'field' }, 'Size', segmented(WHITEBOARD_SIZES.map((s) => [s.id, s.title]), opt.size, (v) => { opt.size = v; hint(); redraw(); }), sizeHint),
        field('Background', segmented(WHITEBOARD_BACKGROUNDS.map((id) => [id, templateTitle(id)]), opt.background, (v) => { opt.background = v; redraw(); })),
        field('Board colour', swatchRow(PAPER_COLOURS, opt.paper, (hex) => { opt.paper = hex; redraw(); })),
        h('div', { class: 'row-btns end' },
          h('button', { class: 'btn', text: 'Cancel', onClick: close }),
          h('button', { class: 'btn primary', text: 'Create whiteboard', onClick: () => {
            const s = WHITEBOARD_SIZES.find((x) => x.id === opt.size);
            const note = app.lib.createNote({
              title: opt.title.trim() || 'Whiteboard', template: opt.background, folderId: app.folder !== 'all' ? app.folder : null,
              kind: 'whiteboard', width: s.w, height: s.h, paper: opt.paper, pageNumbers: false, pageCount: 1,
            });
            close();
            openEditor(note.id);
          } }))),
      h('div', { class: 'setup-preview' }, h('div', { class: 'nb-wrap' }, preview))),
  { wide: true });
}

// ---------- editor ----------

function openEditor(id) {
  setView('editor');
  app.editor?.destroy();
  app.editor = new Editor(root, app.lib, id, { onClose: closeEditor });
}

function closeEditor() {
  app.editor?.destroy();
  app.editor = null;
  showLibrary();
}

// ---------- settings ----------

async function showSettings() {
  const usage = h('p', { class: 'hint', text: 'Checking storage…' });
  app.api.stats().then((s) => (usage.textContent = `Storage used: ${formatBytes(s.bytes)} of ${formatBytes(s.limit)} (${s.objects} items).`)).catch(() => (usage.textContent = ''));

  const msg = h('p', { class: 'error', role: 'alert' });
  const ok = h('p', { class: 'success', role: 'status' });
  const cur = h('input', { type: 'password', autocomplete: 'current-password', required: true });
  const n1 = h('input', { type: 'password', autocomplete: 'new-password', required: true });
  const n2 = h('input', { type: 'password', autocomplete: 'new-password', required: true });
  const field = (t, i) => h('label', { class: 'field' }, t, i);
  const pwForm = h('form', { class: 'stack' },
    h('h3', { text: 'Change password' }), field('Current password', cur), field('New password', n1), field('Type the new one again', n2),
    h('button', { class: 'btn', type: 'submit', text: 'Change password' }));
  pwForm.addEventListener('submit', (e) => {
    e.preventDefault();
    msg.textContent = ok.textContent = '';
    busy($('button', pwForm), 'Changing…', async () => {
      try {
        checkPassword(n1.value, n2.value);
        const api = app.api;
        const email = app.user.email;
        const pre = await api.prelogin(email);
        const current = await C.stretch(cur.value, pre.salt, pre.iterations);
        const salt = newSalt();
        const next = await C.stretch(n1.value, salt, pre.iterations);
        const found = await fetchEnvelope(api);
        // Keep both passwords able to unlock until the change has gone through, in case the connection drops.
        const pending = await C.addPendingPassword(found.envelope, app.master, next.encKey);
        const r1 = await putEnvelope(api, pending, found.version);
        await api.changePassword(current.loginKey, next.loginKey, salt);
        const final = await C.rewrapPassword(pending, app.master, next.encKey);
        await putEnvelope(api, final, r1.version);
        cur.value = n1.value = n2.value = '';
        ok.textContent = 'Password changed. Other devices will ask for the new password.';
      } catch (err) {
        msg.textContent = friendly(err);
      }
    });
  });

  const recoveryBtn = h('button', { class: 'btn', text: 'Make a new recovery key' });
  recoveryBtn.addEventListener('click', () => {
    if (!confirm('This replaces your old recovery key. The old one will stop working. Continue?')) return;
    busy(recoveryBtn, 'Working…', async () => {
      try {
        const found = await fetchEnvelope(app.api);
        const next = await C.rewrapRecovery(found.envelope, app.master);
        await putEnvelope(app.api, next.envelope, found.version);
        showRecovery(next.recoveryKey, async () => { showLibrary(); });
      } catch (err) {
        msg.textContent = friendly(err);
      }
    });
  });

  const content = h('div', { class: 'stack' },
    h('p', {}, 'Signed in as ', h('strong', { text: app.user.email }), app.user.role === 'admin' ? ' (administrator)' : ''),
    usage, pwForm, msg, ok,
    h('hr'),
    h('h3', { text: 'Recovery' }),
    h('p', { class: 'hint', text: 'Your recovery key can unlock your notes if you forget your password.' }),
    recoveryBtn,
    h('hr'),
    app.user.role === 'admin' ? h('p', {}, h('a', { href: 'admin.html', text: 'Open the administrator page' })) : null,
    h('div', { class: 'row-btns' },
      h('button', { class: 'btn', text: 'Sign out and forget this device', onClick: () => signOut() })));
  modal('Settings', () => content);
}

// ---------- start-up ----------

window.addEventListener('beforeunload', (e) => {
  if (app.lib?.hasUnsaved()) {
    e.preventDefault();
    e.returnValue = '';
  }
});
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') app.lib?.flush().catch(() => {});
});

(async function boot() {
  loading('Opening Inkwell…');
  const saved = readSession();
  if (saved && Date.now() < saved.expires) {
    try {
      const master = await deviceVault.load();
      if (master) {
        const api = new Api(saved.api, saved.token);
        await api.me();
        return await start(api, { user: saved.user, expires: saved.expires }, master, true);
      }
    } catch {
      /* fall through to the sign-in screen */
    }
  }
  saveSession(false);
  showAuth();
})();

export { templateTitle };
