// The library: decrypted notes held in memory, kept in sync with the server.
//
// Object ids on the server:
//   <note uuid>   kind "note"     one JSON document per note (all pages, strokes, objects)
//   "folders"     kind "folders"  { v: 1, folders: [{ id, name }] }
//   "templates"   kind "template" { v: 1, templates: [...] }   (made on the iPad; kept untouched here)
//   img-<random>  kind "image"    raw picture bytes
//   "envelope"    kind "envelope" the wrapped master key (handled in app.js)

import { openJson, sealJson, sealBlob, openBlob, toB64Url, randomBytes } from './crypto.js';
import { blobCache } from './idb.js';
import { ApiError } from './api.js';

const KINDS = new Set(['note', 'folders', 'template']);
const SAVE_DELAY = 1200;
const RETRY_DELAY = 10000;

export const uuid = () => crypto.randomUUID().toUpperCase();
export const newPage = () => ({ id: uuid(), strokes: [], images: [], objects: [] });

async function pool(items, size, fn) {
  const queue = [...items];
  await Promise.all(
    Array.from({ length: Math.min(size, queue.length) }, async () => {
      while (queue.length) await fn(queue.shift());
    }),
  );
}

export class Library extends EventTarget {
  constructor(api, master) {
    super();
    this.api = api;
    this.master = master;
    this.items = new Map(); // id -> { kind, data, version, dirty, saving, again, timer, retry }
    this.cursor = 0;
    this.status = 'idle'; // idle | syncing | synced | saving | offline
    this.statusDetail = '';
    this.images = new Map(); // image id -> loaded HTMLImageElement
    this.imageLoads = new Map(); // image id -> Promise
    this.pollTimer = null;
    if (!this.items.has('folders')) this.items.set('folders', this.blank('folders', { v: 1, folders: [] }));
  }

  blank(kind, data) {
    return { kind, data, version: null, dirty: false, saving: false, again: false, timer: null, retry: false };
  }

  emit(type, detail) {
    this.dispatchEvent(new CustomEvent(type, { detail }));
  }

  setStatus(status, detail = '') {
    this.status = status;
    this.statusDetail = detail;
    this.emit('status', { status, detail });
  }

  // ---------- reading ----------

  get folders() {
    return this.items.get('folders').data.folders;
  }

  notes() {
    return [...this.items.values()].filter((i) => i.kind === 'note').map((i) => i.data);
  }

  note(id) {
    const item = this.items.get(id);
    return item && item.kind === 'note' ? item.data : null;
  }

  hasUnsaved() {
    return [...this.items.values()].some((i) => i.dirty || i.saving);
  }

  // ---------- syncing down ----------

  async load() {
    this.setStatus('syncing');
    let more = true;
    while (more) {
      const page = await this.api.changes(this.cursor);
      await this.apply(page.changes);
      this.cursor = page.cursor;
      more = page.more;
    }
    this.setStatus(this.hasUnsaved() ? 'saving' : 'synced');
  }

  async apply(changes) {
    const todo = [];
    for (const c of changes) {
      if (!KINDS.has(c.kind)) continue;
      if (c.deleted) {
        if (c.kind === 'note' && this.items.has(c.id)) {
          this.items.delete(c.id);
          this.emit('removed', { id: c.id });
        }
        continue;
      }
      const known = this.items.get(c.id);
      if (known && known.version !== null && known.version >= c.version) continue;
      todo.push(c);
    }
    await pool(todo, 6, (c) => this.fetchItem(c));
    if (todo.length) this.emit('notes');
  }

  async fetchItem(c) {
    let sealed;
    const cached = await blobCache.get(c.id);
    if (cached && cached.version === c.version) {
      sealed = cached.bytes;
    } else {
      const res = await this.api.getBlob(c.id, c.version);
      sealed = res.bytes;
      await blobCache.put(c.id, { version: c.version, bytes: sealed });
    }
    const data = await openJson(this.master, c.kind, c.id, sealed);
    const existing = this.items.get(c.id);
    if (existing && (existing.dirty || existing.saving)) {
      existing.remoteNewer = true; // keep what is on screen; the next save keeps both in history
      this.emit('remote', { id: c.id, kept: true });
      return;
    }
    const item = existing || this.blank(c.kind, data);
    item.data = data;
    item.version = c.version;
    this.items.set(c.id, item);
    if (existing) this.emit('remote', { id: c.id, kept: false });
  }

  startPolling(ms = 30000) {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      if (document.visibilityState === 'visible') this.load().catch((e) => this.handleError(e));
    }, ms);
  }

  stopPolling() {
    clearInterval(this.pollTimer);
    this.pollTimer = null;
  }

  handleError(err) {
    if (err instanceof ApiError && err.status === 401) {
      this.emit('signed-out');
      return;
    }
    this.setStatus('offline', err.message);
  }

  // ---------- writing ----------

  /** Makes a note, notebook or whiteboard. Sizes are in points at 96 dpi (A4 portrait is 794 x 1123). */
  createNote({
    title = 'Untitled note', template = 'ruled', folderId = null,
    kind = 'note', width = 794, height = 1123, cover = null, paper = '#FFFFFF', pageNumbers = false, pageCount = 1,
  } = {}) {
    const id = uuid();
    const data = {
      v: 1, id, title, folderId, template, modified: Date.now(),
      pages: Array.from({ length: Math.max(1, pageCount) }, () => newPage()),
      kind, pageWidth: width, pageHeight: height, paper, pageNumbers,
    };
    if (cover) data.cover = cover;
    const item = this.blank('note', data);
    this.items.set(id, item);
    item.dirty = true;
    this.schedule(id, 100);
    this.emit('notes');
    return data;
  }

  duplicateNote(id) {
    const src = this.note(id);
    if (!src) return null;
    const copy = JSON.parse(JSON.stringify(src));
    copy.id = uuid();
    copy.title = `${src.title} copy`;
    copy.modified = Date.now();
    for (const p of copy.pages) p.id = uuid();
    const item = this.blank('note', copy);
    item.dirty = true;
    this.items.set(copy.id, item);
    this.schedule(copy.id, 100);
    this.emit('notes');
    return copy;
  }

  /** Call after changing a note. */
  touch(id) {
    const item = this.items.get(id);
    if (!item) return;
    item.dirty = true;
    if (item.kind === 'note') item.data.modified = Date.now();
    this.setStatus('saving');
    this.schedule(id, SAVE_DELAY);
  }

  schedule(id, delay) {
    const item = this.items.get(id);
    if (!item) return;
    clearTimeout(item.timer);
    item.timer = setTimeout(() => this.save(id), delay);
  }

  async save(id) {
    const item = this.items.get(id);
    if (!item || !item.dirty) return;
    if (item.saving) {
      item.again = true;
      return;
    }
    clearTimeout(item.timer);
    item.saving = true;
    item.dirty = false;
    let failed = false;
    try {
      const sealed = await sealJson(this.master, item.kind, id, item.data);
      const res = await this.api.putBlob(id, item.kind, sealed, item.version);
      item.version = res.version;
      item.remoteNewer = false;
      await blobCache.put(id, { version: res.version, bytes: sealed });
      if (res.conflict) this.emit('conflict', { id });
    } catch (err) {
      failed = true;
      item.dirty = true;
      this.handleError(err);
      if (!(err instanceof ApiError && err.status === 401)) item.timer = setTimeout(() => this.save(id), RETRY_DELAY);
    } finally {
      item.saving = false;
      if (!failed && (item.again || item.dirty)) {
        item.again = false;
        this.schedule(id, 300);
      }
    }
    if (!failed && !this.hasUnsaved()) this.setStatus('synced');
  }

  async flush() {
    await Promise.all([...this.items.keys()].map((id) => this.save(id)));
  }

  async deleteNote(id) {
    const item = this.items.get(id);
    if (!item) return;
    clearTimeout(item.timer);
    this.items.delete(id);
    this.emit('notes');
    try {
      await this.api.deleteBlob(id);
    } catch (err) {
      if (!(err instanceof ApiError && err.status === 404)) this.handleError(err);
    }
  }

  // ---------- folders ----------

  touchFolders() {
    this.touch('folders');
    this.emit('notes');
  }

  addFolder(name) {
    const folder = { id: uuid(), name };
    this.folders.push(folder);
    this.touchFolders();
    return folder;
  }

  renameFolder(id, name) {
    const f = this.folders.find((x) => x.id === id);
    if (f) f.name = name;
    this.touchFolders();
  }

  deleteFolder(id) {
    const list = this.items.get('folders').data;
    list.folders = list.folders.filter((f) => f.id !== id);
    for (const note of this.notes()) {
      if (note.folderId === id) {
        note.folderId = null;
        this.touch(note.id);
      }
    }
    this.touchFolders();
  }

  moveNote(id, folderId) {
    const n = this.note(id);
    if (!n) return;
    n.folderId = folderId;
    this.touch(id);
    this.emit('notes');
  }

  // ---------- pictures ----------

  async addImage(bytes) {
    const id = `img-${toB64Url(randomBytes(12))}`;
    const sealed = await sealBlob(this.master, 'image', id, bytes);
    await this.api.putBlob(id, 'image', sealed);
    await blobCache.put(id, { version: 1, bytes: sealed });
    return id;
  }

  /** Resolves to a loaded HTMLImageElement, cached by id. */
  loadImage(id, mime = 'image/jpeg') {
    if (this.imageLoads.has(id)) return this.imageLoads.get(id);
    const promise = (async () => {
      let sealed;
      const cached = await blobCache.get(id);
      if (cached) {
        sealed = cached.bytes;
      } else {
        sealed = (await this.api.getBlob(id)).bytes;
        await blobCache.put(id, { version: 1, bytes: sealed });
      }
      const bytes = await openBlob(this.master, 'image', id, sealed);
      const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
      const el = new Image();
      // The load event, not decode(): browsers can hold decode() back while a tab is in the background.
      await new Promise((resolve, reject) => {
        el.onload = resolve;
        el.onerror = () => reject(new Error('That picture could not be read.'));
        el.src = url;
      });
      this.images.set(id, el);
      this.emit('image', { id });
      return el;
    })();
    promise.catch(() => this.imageLoads.delete(id));
    this.imageLoads.set(id, promise);
    return promise;
  }

  /** Starts loading every picture a page uses. */
  preloadPage(page) {
    const wanted = [];
    if (page.background) wanted.push([page.background, 'image/jpeg']);
    for (const im of page.images || []) wanted.push([im.file, im.mime || 'image/jpeg']);
    for (const [id, mime] of wanted) this.loadImage(id, mime).catch(() => {});
  }
}
