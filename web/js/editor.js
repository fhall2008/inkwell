// The note editor: pages with pen, highlighter and eraser, plus text boxes, sticky notes,
// checklists, tables, stamps and pictures that can be moved and resized in "edit objects" mode.

import { h, clear, toast, popMenu, download, safeFilename } from './dom.js';
import { PAGE_W, PAGE_H, TEMPLATES, templateTitle } from './templates.js';
import { drawPaper, drawInk, drawStroke, distanceToStroke, flattenPage, objectFont, rowHeight, layoutHeight } from './render.js';
import { newPage, uuid } from './store.js';

const COLORS = ['#1B2430', '#2F5BEA', '#D97757', '#4FB286', '#C0392B', '#8E44AD'];
const HIGHLIGHTS = ['#FFD84D', '#7BE0AD', '#8FB5FF', '#FF9EB5', '#D9A7FF', '#FFB26B'];
const DESIGNS = [['sans', 'Sans'], ['serif', 'Serif'], ['rounded', 'Rounded'], ['mono', 'Mono']];
const LISTS = [['none', 'No list'], ['bullet', 'Bullets'], ['numbered', 'Numbered']];
const STAMPS = ['APPROVED', 'DRAFT', 'DONE', 'URGENT', 'CONFIDENTIAL', 'REVIEWED'];

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/** Keeps receiving a pointer's events outside the element. Browsers throw if the pointer isn't active. */
function capture(el, pointerId) {
  try {
    el.setPointerCapture(pointerId);
  } catch {
    /* not capturable; drawing still works while the pointer stays over the page */
  }
}
const store = {
  get: (k, d) => {
    try {
      return localStorage.getItem(k) ?? d;
    } catch {
      return d;
    }
  },
  set: (k, v) => {
    try {
      localStorage.setItem(k, v);
    } catch {
      /* ignore */
    }
  },
};

/** New object with the same fields the iPad app uses. */
export function makeObject(kind, text = '') {
  const o = {
    id: uuid(), kind, x: 80, y: 160, width: 220, height: 120,
    colorHex: '#1B2430', fillHex: null, lineWidth: 3, text: '', fontSize: 18,
    design: 'sans', bold: false, italic: false, list: 'none', items: [], cells: [],
  };
  switch (kind) {
    case 'text':
      o.width = 400; o.height = 40; o.text = text;
      break;
    case 'sticky':
      o.width = 220; o.height = 180; o.fillHex = '#FFE98A'; o.fontSize = 17; o.text = text;
      break;
    case 'checklist':
      o.width = 320;
      o.items = [0, 1, 2].map(() => ({ id: uuid(), text: '', done: false }));
      break;
    case 'table':
      o.width = 420; o.fontSize = 16;
      o.cells = [0, 1, 2].map(() => ['', '', '']);
      break;
    case 'stamp':
      o.width = 240; o.height = 60; o.text = text || 'APPROVED'; o.colorHex = '#C0392B'; o.fontSize = 26; o.bold = true;
      break;
  }
  return o;
}

const objectHeight = (o) => (o.kind === 'text' ? null : o.kind === 'checklist' || o.kind === 'table' ? layoutHeight(o) : o.height);

function autosize(ta) {
  ta.style.height = 'auto';
  ta.style.height = `${ta.scrollHeight}px`;
}

// ---------------------------------------------------------------------------------------------

class PageView {
  constructor(editor, page) {
    this.editor = editor;
    this.page = page;
    this.scale = 1;
    this.k = 1;
    this.rendered = false;
    this.paper = h('canvas', { class: 'paper' });
    this.ink = h('canvas', { class: 'ink' });
    this.live = h('canvas', { class: 'live' });
    this.items = h('div', { class: 'items' });
    this.scaler = h('div', { class: 'scaler' }, this.paper, this.ink, this.live, this.items);
    this.el = h('section', { class: 'page', 'data-page': page.id }, this.scaler);
    this.live.addEventListener('pointerdown', (e) => editor.pointerDown(e, this));
    this.live.addEventListener('pointermove', (e) => editor.pointerMove(e, this));
    this.live.addEventListener('pointerup', (e) => editor.pointerUp(e, this));
    this.live.addEventListener('pointercancel', (e) => editor.pointerUp(e, this));
  }

  applySize(scale) {
    this.scale = scale;
    this.el.style.width = `${Math.round(PAGE_W * scale)}px`;
    this.el.style.height = `${Math.round(PAGE_H * scale)}px`;
    this.scaler.style.transform = `scale(${scale})`;
    if (this.rendered) this.render();
  }

  ctx(canvas) {
    const x = canvas.getContext('2d');
    x.setTransform(this.k, 0, 0, this.k, 0, 0);
    return x;
  }

  render() {
    this.k = clamp((window.devicePixelRatio || 1) * this.scale, 0.5, 3);
    for (const c of [this.paper, this.ink, this.live]) {
      c.width = Math.round(PAGE_W * this.k);
      c.height = Math.round(PAGE_H * this.k);
    }
    this.rendered = true;
    this.redrawPaper();
    this.redrawInk();
    this.buildItems();
  }

  release() {
    for (const c of [this.paper, this.ink, this.live]) {
      c.width = 1; // 0 isn't allowed (it falls back to 300x150)
      c.height = 1;
    }
    this.rendered = false;
  }

  redrawPaper() {
    if (!this.rendered) return;
    const edit = this.editor.editMode;
    const x = this.ctx(this.paper);
    x.clearRect(0, 0, PAGE_W, PAGE_H);
    drawPaper(x, this.page, this.editor.note.template, this.editor.lib.images, { objects: !edit, pictures: !edit });
  }

  redrawInk() {
    if (!this.rendered) return;
    const x = this.ctx(this.ink);
    x.clearRect(0, 0, PAGE_W, PAGE_H);
    drawInk(x, this.page);
  }

  redrawLive(stroke) {
    const x = this.ctx(this.live);
    x.clearRect(0, 0, PAGE_W, PAGE_H);
    if (stroke) drawStroke(x, stroke);
  }

  // ----- editable items (edit mode) -----

  buildItems() {
    clear(this.items);
    const ed = this.editor;
    this.items.classList.toggle('on', ed.editMode);
    if (!ed.editMode || !this.rendered) return;
    for (const im of this.page.images) this.items.append(this.imageItem(im));
    for (const o of this.page.objects) this.items.append(this.objectItem(o));
    ed.markSelection();
  }

  /** Drag to move, or resize from the corner. */
  startDrag(e, mode, el, model, { resizeHeight = false, keepRatio = false } = {}) {
    e.preventDefault();
    e.stopPropagation();
    const target = e.currentTarget;
    capture(target, e.pointerId);
    const sx = e.clientX, sy = e.clientY;
    const ox = model.x, oy = model.y, ow = model.width, oh = model.height;
    const move = (ev) => {
      const dx = (ev.clientX - sx) / this.scale;
      const dy = (ev.clientY - sy) / this.scale;
      if (mode === 'move') {
        model.x = clamp(ox + dx, -model.width + 30, PAGE_W - 30);
        model.y = clamp(oy + dy, -20, PAGE_H - 30);
        el.style.left = `${model.x}px`;
        el.style.top = `${model.y}px`;
      } else {
        model.width = Math.max(40, ow + dx);
        el.style.width = `${model.width}px`;
        if (keepRatio) {
          model.height = (model.width * oh) / ow;
          el.style.height = `${model.height}px`;
        } else if (resizeHeight) {
          model.height = Math.max(24, oh + dy);
          el.style.height = `${model.height}px`;
        }
      }
    };
    const up = () => {
      target.removeEventListener('pointermove', move);
      target.removeEventListener('pointerup', up);
      target.removeEventListener('pointercancel', up);
      this.editor.changed();
    };
    target.addEventListener('pointermove', move);
    target.addEventListener('pointerup', up);
    target.addEventListener('pointercancel', up);
  }

  handles(el, model, type, opts) {
    return [
      h('div', { class: 'handle move', title: 'Drag to move', onPointerdown: (e) => this.startDrag(e, 'move', el, model) }, '✥'),
      h('div', { class: 'handle resize', title: 'Drag to resize', onPointerdown: (e) => this.startDrag(e, 'resize', el, model, opts) }, '⤡'),
    ];
  }

  frame(model, type, height) {
    return h('div', {
      class: `item ${type === 'image' ? 'img' : `obj ${model.kind}`}`,
      'data-id': model.id,
      style: {
        left: `${model.x}px`, top: `${model.y}px`, width: `${model.width}px`,
        height: height === null ? 'auto' : `${height}px`,
      },
    });
  }

  imageItem(im) {
    const el = this.frame(im, 'image', im.height);
    const src = this.editor.lib.images.get(im.file)?.src || '';
    const img = h('img', { src, alt: 'Picture', draggable: false });
    img.addEventListener('pointerdown', (e) => {
      this.editor.select(this, im, 'image');
      this.startDrag(e, 'move', el, im);
    });
    el.append(img, ...this.handles(el, im, 'image', { keepRatio: true }));
    el.addEventListener('pointerdown', () => this.editor.select(this, im, 'image'), true);
    return el;
  }

  textArea(o, fill) {
    const ed = this.editor;
    const ta = h('textarea', {
      class: 'obj-text', rows: 1, placeholder: o.kind === 'sticky' ? 'Note' : 'Type here', value: o.text || '',
      style: { font: objectFont(o), color: o.colorHex, height: fill ? '100%' : 'auto' },
      onInput: () => {
        o.text = ta.value;
        if (!fill) autosize(ta);
        ed.changed();
      },
    });
    if (!fill) requestAnimationFrame(() => autosize(ta));
    return ta;
  }

  checklistRow(o, item) {
    const ed = this.editor;
    const text = h('input', {
      type: 'text', class: 'cl-text', value: item.text, placeholder: 'Item',
      style: { textDecoration: item.done ? 'line-through' : 'none' },
      onInput: (e) => {
        item.text = e.target.value;
        ed.changed();
      },
    });
    const box = h('input', {
      type: 'checkbox', checked: item.done, style: { width: `${o.fontSize}px`, height: `${o.fontSize}px` },
      onChange: (e) => {
        item.done = e.target.checked;
        text.style.textDecoration = item.done ? 'line-through' : 'none';
        ed.changed();
      },
    });
    return h('label', { class: 'row', style: { height: `${rowHeight(o)}px` } }, box, text);
  }

  objectItem(o) {
    const ed = this.editor;
    const el = this.frame(o, 'object', objectHeight(o));
    let body;
    if (o.kind === 'text') {
      body = this.textArea(o, false);
    } else if (o.kind === 'sticky') {
      body = h('div', { class: 'sticky', style: { background: o.fillHex || '#FFE98A' } }, this.textArea(o, true));
    } else if (o.kind === 'checklist') {
      body = h(
        'div',
        { class: 'checklist', style: { font: objectFont(o), color: o.colorHex } },
        o.items.map((item) => this.checklistRow(o, item)),
      );
    } else if (o.kind === 'table') {
      const cols = o.cells[0]?.length || 1;
      body = h(
        'div',
        { class: 'table', style: { gridTemplateColumns: `repeat(${cols}, 1fr)`, font: objectFont(o), color: o.colorHex } },
        o.cells.flatMap((row, r) =>
          row.map((value, c) =>
            h('input', {
              type: 'text', value, style: { height: `${rowHeight(o)}px`, borderColor: o.colorHex },
              onInput: (e) => {
                o.cells[r][c] = e.target.value;
                ed.changed();
              },
            }),
          ),
        ),
      );
    } else {
      body = h('div', { class: 'stamp', style: { color: o.colorHex, borderColor: o.colorHex, font: objectFont(o) }, text: (o.text || '').toUpperCase() });
    }
    el.append(body, ...this.handles(el, o, 'object', { resizeHeight: o.kind === 'sticky' || o.kind === 'stamp' }));
    el.addEventListener('pointerdown', () => ed.select(this, o, 'object'), true);
    return el;
  }
}

// ---------------------------------------------------------------------------------------------

export class Editor {
  constructor(root, lib, noteId, { onClose }) {
    this.root = root;
    this.lib = lib;
    this.noteId = noteId;
    this.onClose = onClose;
    this.tool = 'pen';
    this.penColor = store.get('inkwell.color', COLORS[0]);
    this.hlColor = store.get('inkwell.hlColor', HIGHLIGHTS[0]);
    this.width = Number(store.get('inkwell.width', '2.5'));
    this.penOnly = store.get('inkwell.penOnly', '1') === '1';
    this.editMode = false;
    this.selected = null; // { pv, model, type }
    this.undoStack = [];
    this.redoStack = [];
    this.views = [];
    this.drawing = null;
    this.erasing = null;
    this.panning = null;

    this.build();
    this.renderPages();

    this.onStatus = () => this.updateStatus();
    this.onRemote = (e) => this.handleRemote(e.detail);
    this.onConflict = (e) => {
      if (e.detail.id === this.noteId) toast('Another device saved this note too. Yours replaced it; the older copy is kept in history.', 7000);
    };
    this.onImage = () => {
      for (const pv of this.views) {
        pv.redrawPaper();
        if (this.editMode) pv.buildItems();
      }
    };
    this.onKey = (e) => this.keyDown(e);
    lib.addEventListener('status', this.onStatus);
    lib.addEventListener('remote', this.onRemote);
    lib.addEventListener('conflict', this.onConflict);
    lib.addEventListener('image', this.onImage);
    document.addEventListener('keydown', this.onKey);
    this.resizeObserver = new ResizeObserver(() => this.layout());
    this.resizeObserver.observe(this.scroller);
    this.updateStatus();
  }

  get note() {
    return this.lib.note(this.noteId);
  }

  destroy() {
    this.lib.removeEventListener('status', this.onStatus);
    this.lib.removeEventListener('remote', this.onRemote);
    this.lib.removeEventListener('conflict', this.onConflict);
    this.lib.removeEventListener('image', this.onImage);
    document.removeEventListener('keydown', this.onKey);
    this.resizeObserver.disconnect();
    this.observer?.disconnect();
    clear(this.root);
  }

  // ---------- building the screen ----------

  build() {
    this.titleInput = h('input', {
      class: 'ed-title', type: 'text', value: this.note.title, 'aria-label': 'Note title',
      onInput: () => {
        this.note.title = this.titleInput.value;
        this.changed();
      },
    });
    this.statusEl = h('span', { class: 'ed-status', role: 'status' });
    this.undoBtn = h('button', { class: 'icon', title: 'Undo', 'aria-label': 'Undo', text: '↶', onClick: () => this.undo() });
    this.redoBtn = h('button', { class: 'icon', title: 'Redo', 'aria-label': 'Redo', text: '↷', onClick: () => this.redo() });
    this.editBtn = h('button', {
      class: 'btn', 'aria-pressed': 'false', title: 'Move, resize and edit text boxes, pictures and other objects',
      text: 'Edit objects', onClick: () => this.setEditMode(!this.editMode),
    });
    this.toolButtons = {
      pen: h('button', { class: 'tool', text: 'Pen', onClick: () => this.setTool('pen') }),
      highlighter: h('button', { class: 'tool', text: 'Highlighter', onClick: () => this.setTool('highlighter') }),
      eraser: h('button', { class: 'tool', text: 'Eraser', onClick: () => this.setTool('eraser') }),
    };
    this.swatchBox = h('div', { class: 'swatches' });
    this.colorInput = h('input', {
      type: 'color', value: this.penColor, 'aria-label': 'Custom colour', title: 'Custom colour',
      onInput: () => this.setColor(this.colorInput.value),
    });
    this.widthInput = h('input', {
      type: 'range', min: '1', max: '10', step: '0.5', value: String(this.width), 'aria-label': 'Pen size',
      onInput: () => {
        this.width = Number(this.widthInput.value);
        store.set('inkwell.width', String(this.width));
      },
    });
    this.penOnlyBox = h('input', {
      type: 'checkbox', checked: this.penOnly,
      onChange: () => {
        this.penOnly = this.penOnlyBox.checked;
        store.set('inkwell.penOnly', this.penOnly ? '1' : '0');
      },
    });

    const insertBtn = h('button', { class: 'btn', text: 'Insert ▾' });
    insertBtn.addEventListener('click', () => this.insertMenu(insertBtn));
    const pagesBtn = h('button', { class: 'btn', text: 'Pages ▾' });
    pagesBtn.addEventListener('click', () => this.pagesMenu(pagesBtn));
    const exportBtn = h('button', { class: 'btn primary', text: 'Export ▾' });
    exportBtn.addEventListener('click', () => this.exportMenu(exportBtn));

    this.fileInput = h('input', { type: 'file', accept: 'image/*', hidden: true, onChange: () => this.pickedPicture(this.fileInput) });
    this.cameraInput = h('input', {
      type: 'file', accept: 'image/*', capture: 'environment', hidden: true, onChange: () => this.pickedPicture(this.cameraInput),
    });

    this.inspector = h('div', { class: 'ed-inspector', hidden: true });
    this.pagesEl = h('div', { class: 'ed-pages' });
    this.scroller = h('div', { class: 'ed-scroll' }, this.pagesEl);

    clear(this.root);
    this.root.append(
      h(
        'div',
        { class: 'editor' },
        h(
          'header',
          { class: 'ed-top' },
          h('div', { class: 'ed-row' },
            h('button', { class: 'btn', text: '‹ Library', onClick: () => this.close() }),
            this.titleInput, this.statusEl, this.undoBtn, this.redoBtn, insertBtn, this.editBtn, pagesBtn, exportBtn),
          h('div', { class: 'ed-row tools' },
            ...Object.values(this.toolButtons), this.swatchBox, this.colorInput,
            h('label', { class: 'size' }, 'Size', this.widthInput),
            h('label', { class: 'check' }, this.penOnlyBox, 'Pen only (finger scrolls)')),
          this.inspector,
        ),
        this.scroller,
        this.fileInput,
        this.cameraInput,
      ),
    );
    this.renderSwatches();
    this.setTool('pen');
  }

  /** The colour of whichever tool is active (the eraser shows the pen's). */
  get color() {
    return this.tool === 'highlighter' ? this.hlColor : this.penColor;
  }

  renderSwatches() {
    clear(this.swatchBox);
    const palette = this.tool === 'highlighter' ? HIGHLIGHTS : COLORS;
    for (const c of palette) {
      this.swatchBox.append(
        h('button', {
          class: `swatch${c.toLowerCase() === this.color.toLowerCase() ? ' on' : ''}`,
          style: { background: c }, title: c, 'aria-label': `Colour ${c}`, onClick: () => this.setColor(c),
        }),
      );
    }
  }

  setColor(c) {
    if (this.tool === 'eraser') this.setTool('pen');
    if (this.tool === 'highlighter') {
      this.hlColor = c;
      store.set('inkwell.hlColor', c);
    } else {
      this.penColor = c;
      store.set('inkwell.color', c);
    }
    this.colorInput.value = c;
    this.renderSwatches();
  }

  setTool(tool) {
    this.tool = tool;
    if (this.colorInput) this.colorInput.value = this.color;
    if (this.swatchBox) this.renderSwatches();
    for (const [name, btn] of Object.entries(this.toolButtons)) {
      btn.classList.toggle('on', name === tool);
      btn.setAttribute('aria-pressed', String(name === tool));
    }
    if (this.editMode) this.setEditMode(false);
  }

  updateStatus() {
    const { status, statusDetail } = this.lib;
    const text = { synced: 'Saved', saving: 'Saving…', syncing: 'Syncing…', offline: `Offline${statusDetail ? `: ${statusDetail}` : ''}`, idle: '' }[status] ?? '';
    this.statusEl.textContent = text;
    this.statusEl.classList.toggle('bad', status === 'offline');
  }

  updateUndo() {
    this.undoBtn.disabled = !this.undoStack.length;
    this.redoBtn.disabled = !this.redoStack.length;
  }

  async close() {
    await this.lib.flush();
    this.onClose();
  }

  // ---------- pages ----------

  renderPages() {
    this.observer?.disconnect();
    this.select(null);
    clear(this.pagesEl);
    this.views = this.note.pages.map((p) => new PageView(this, p));
    const byEl = new Map(this.views.map((v) => [v.el, v]));
    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const pv = byEl.get(entry.target);
          if (!pv) continue;
          if (entry.isIntersecting) {
            this.lib.preloadPage(pv.page);
            if (!pv.rendered) pv.render();
          } else if (pv.rendered && this.drawing?.pv !== pv && document.visibilityState === 'visible') {
            pv.release(); // far off screen: free its memory (not while the whole tab is hidden)
          }
        }
      },
      { root: this.scroller, rootMargin: '900px 0px' },
    );
    for (const pv of this.views) {
      this.pagesEl.append(pv.el);
      this.observer.observe(pv.el);
    }
    this.layout();
    // Don't depend on the visibility observer for the pages the person sees first.
    for (const pv of this.views.slice(0, 2)) {
      this.lib.preloadPage(pv.page);
      if (!pv.rendered) pv.render();
    }
    this.updateUndo();
  }

  layout() {
    const avail = Math.max(260, this.scroller.clientWidth - 24);
    const scale = Math.min(avail / PAGE_W, 1.4);
    for (const pv of this.views) pv.applySize(scale);
  }

  activeView() {
    const box = this.scroller.getBoundingClientRect();
    const mid = box.top + box.height / 2;
    let best = this.views[0];
    let bestDist = Infinity;
    for (const pv of this.views) {
      const r = pv.el.getBoundingClientRect();
      const d = Math.abs(r.top + r.height / 2 - mid);
      if (d < bestDist) {
        best = pv;
        bestDist = d;
      }
    }
    return best;
  }

  changed() {
    this.lib.touch(this.noteId);
    this.updateUndo();
  }

  handleRemote({ id, kept }) {
    if (id !== this.noteId) return;
    if (kept) {
      toast('This note was also changed on another device. Your version will be saved on top; the other is kept in history.', 7000);
      return;
    }
    toast('This note was updated from another device.');
    this.undoStack = [];
    this.redoStack = [];
    this.titleInput.value = this.note.title;
    this.renderPages();
  }

  addPage() {
    const at = this.views.indexOf(this.activeView());
    this.note.pages.splice(at + 1, 0, newPage());
    this.changed();
    this.renderPages();
    this.scrollToPage(at + 1);
  }

  duplicatePage() {
    const at = this.views.indexOf(this.activeView());
    const copy = JSON.parse(JSON.stringify(this.note.pages[at]));
    copy.id = uuid();
    for (const o of copy.objects) o.id = uuid();
    for (const im of copy.images) im.id = uuid();
    this.note.pages.splice(at + 1, 0, copy);
    this.changed();
    this.renderPages();
    this.scrollToPage(at + 1);
  }

  deletePage() {
    if (this.note.pages.length < 2) return toast('A note needs at least one page.');
    const at = this.views.indexOf(this.activeView());
    if (!confirm(`Delete page ${at + 1}? This can't be undone.`)) return;
    this.note.pages.splice(at, 1);
    this.undoStack = [];
    this.redoStack = [];
    this.changed();
    this.renderPages();
  }

  movePage(delta) {
    const at = this.views.indexOf(this.activeView());
    const to = at + delta;
    if (to < 0 || to >= this.note.pages.length) return;
    const [page] = this.note.pages.splice(at, 1);
    this.note.pages.splice(to, 0, page);
    this.changed();
    this.renderPages();
    this.scrollToPage(to);
  }

  scrollToPage(index) {
    requestAnimationFrame(() => this.views[index]?.el.scrollIntoView({ block: 'start', behavior: 'smooth' }));
  }

  changeTemplate(id) {
    this.note.template = id;
    this.changed();
    for (const pv of this.views) pv.redrawPaper();
  }

  // ---------- drawing ----------

  pointer(e, pv) {
    const r = pv.live.getBoundingClientRect();
    return [((e.clientX - r.left) * PAGE_W) / r.width, ((e.clientY - r.top) * PAGE_H) / r.height];
  }

  pointerDown(e, pv) {
    if (this.editMode) return;
    if (e.pointerType === 'touch' && this.penOnly) {
      // The finger scrolls instead of drawing; the canvas can't do this itself because it needs touch-action: none for the pen.
      this.panning = { id: e.pointerId, y: e.clientY, top: this.scroller.scrollTop };
      capture(pv.live, e.pointerId);
      return;
    }
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    e.preventDefault();
    capture(pv.live, e.pointerId);
    this.select(null);
    if (this.tool === 'eraser') {
      this.erasing = { pv, id: e.pointerId, before: pv.page.strokes.slice(), changed: false };
      this.erase(e, pv);
    } else {
      this.drawing = {
        pv, id: e.pointerId,
        stroke: { ink: this.tool === 'highlighter' ? 'highlighter' : 'pen', color: this.color, points: [] },
      };
      this.addPoint(e, pv);
      pv.redrawLive(this.drawing.stroke);
    }
  }

  addPoint(e, pv) {
    const stroke = this.drawing.stroke;
    const [x, y] = this.pointer(e, pv);
    const pressure = e.pointerType === 'pen' && e.pressure > 0 ? e.pressure : 0.5;
    const w =
      stroke.ink === 'highlighter' ? Math.max(14, this.width * 5) : this.width * (e.pointerType === 'pen' ? 0.35 + 1.15 * pressure : 1);
    const last = stroke.points[stroke.points.length - 1];
    if (last && Math.hypot(last[0] - x, last[1] - y) < 0.6) return;
    stroke.points.push([Math.round(x * 10) / 10, Math.round(y * 10) / 10, Math.round(w * 10) / 10]);
  }

  pointerMove(e, pv) {
    if (this.panning && this.panning.id === e.pointerId) {
      this.scroller.scrollTop = this.panning.top - (e.clientY - this.panning.y);
      return;
    }
    if (this.drawing && this.drawing.id === e.pointerId && this.drawing.pv === pv) {
      const batch = e.getCoalescedEvents?.() ?? [];
      for (const ev of batch.length ? batch : [e]) this.addPoint(ev, pv);
      pv.redrawLive(this.drawing.stroke);
    } else if (this.erasing && this.erasing.id === e.pointerId && this.erasing.pv === pv) {
      this.erase(e, pv);
    }
  }

  pointerUp(e, pv) {
    if (this.panning && this.panning.id === e.pointerId) {
      this.panning = null;
      return;
    }
    if (this.drawing && this.drawing.id === e.pointerId) {
      const { stroke } = this.drawing;
      const target = this.drawing.pv;
      this.drawing = null;
      if (stroke.points.length) {
        const before = target.page.strokes.slice();
        target.page.strokes.push(stroke);
        this.pushHistory(target.page.id, before, target.page.strokes.slice());
        drawStroke(target.ctx(target.ink), stroke);
        this.changed();
      }
      target.redrawLive(null);
    } else if (this.erasing && this.erasing.id === e.pointerId) {
      const { pv: target, before, changed } = this.erasing;
      this.erasing = null;
      if (changed) this.pushHistory(target.page.id, before, target.page.strokes.slice());
    }
  }

  erase(e, pv) {
    const [x, y] = this.pointer(e, pv);
    const radius = Math.max(8, this.width * 2.5);
    const keep = pv.page.strokes.filter((s) => {
      const half = Math.max(...s.points.map((p) => p[2])) / 2;
      return distanceToStroke(s, x, y) > radius + half;
    });
    if (keep.length !== pv.page.strokes.length) {
      pv.page.strokes = keep;
      this.erasing.changed = true;
      pv.redrawInk();
      this.changed();
    }
  }

  pushHistory(pageId, before, after) {
    this.undoStack.push({ pageId, before, after });
    if (this.undoStack.length > 200) this.undoStack.shift();
    this.redoStack = [];
    this.updateUndo();
  }

  applyHistory(entry, strokes) {
    const pv = this.views.find((v) => v.page.id === entry.pageId);
    if (!pv) return;
    pv.page.strokes = strokes.slice();
    pv.redrawInk();
    this.changed();
  }

  undo() {
    const entry = this.undoStack.pop();
    if (!entry) return;
    this.redoStack.push(entry);
    this.applyHistory(entry, entry.before);
  }

  redo() {
    const entry = this.redoStack.pop();
    if (!entry) return;
    this.undoStack.push(entry);
    this.applyHistory(entry, entry.after);
  }

  keyDown(e) {
    if (!(e.metaKey || e.ctrlKey) || e.key.toLowerCase() !== 'z') return;
    if (['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
    e.preventDefault();
    if (e.shiftKey) this.redo();
    else this.undo();
  }

  // ---------- objects and pictures ----------

  setEditMode(on) {
    this.editMode = on;
    this.root.classList.toggle('editing', on);
    this.editBtn.classList.toggle('on', on);
    this.editBtn.setAttribute('aria-pressed', String(on));
    if (!on) this.select(null);
    for (const pv of this.views) {
      pv.redrawPaper();
      pv.buildItems();
    }
  }

  select(pv, model, type) {
    this.selected = pv ? { pv, model, type } : null;
    this.markSelection();
    this.renderInspector();
  }

  markSelection() {
    this.root.querySelectorAll('.item.selected').forEach((el) => el.classList.remove('selected'));
    if (this.selected) this.root.querySelector(`.item[data-id="${this.selected.model.id}"]`)?.classList.add('selected');
  }

  insertMenu(anchor) {
    popMenu(anchor, [
      { label: 'Text box', onClick: () => this.insertObject('text') },
      { label: 'Sticky note', onClick: () => this.insertObject('sticky') },
      { label: 'Checklist', onClick: () => this.insertObject('checklist') },
      { label: 'Table', onClick: () => this.insertObject('table') },
      { divider: true },
      ...STAMPS.map((s) => ({ label: `Stamp: ${s}`, onClick: () => this.insertObject('stamp', s) })),
      { label: `Stamp: ${new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}`, onClick: () => this.insertObject('stamp', new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })) },
      { divider: true },
      { label: 'Picture from this device…', onClick: () => this.fileInput.click() },
      { label: 'Take a photo…', onClick: () => this.cameraInput.click() },
    ]);
  }

  insertObject(kind, text = '') {
    const pv = this.activeView();
    if (!pv.rendered) pv.render();
    const o = makeObject(kind, text);
    const offset = (pv.page.objects.length % 8) * 36;
    o.x += offset;
    o.y += offset;
    pv.page.objects.push(o);
    if (!this.editMode) this.setEditMode(true);
    else pv.buildItems();
    this.select(pv, o, 'object');
    this.changed();
    pv.items.querySelector(`.item[data-id="${o.id}"] textarea`)?.focus();
  }

  async pickedPicture(input) {
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    try {
      const bitmap = await createImageBitmap(file);
      const s = Math.min(1, 2000 / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(bitmap.width * s);
      canvas.height = Math.round(bitmap.height * s);
      canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.85));
      const fileId = await this.lib.addImage(new Uint8Array(await blob.arrayBuffer()));
      await this.lib.loadImage(fileId, 'image/jpeg');
      const pv = this.activeView();
      if (!pv.rendered) pv.render();
      const w = Math.min(320, bitmap.width);
      const im = {
        id: uuid(), file: fileId, mime: 'image/jpeg',
        x: (PAGE_W - w) / 2, y: 200, width: w, height: (w * bitmap.height) / bitmap.width,
      };
      pv.page.images.push(im);
      if (!this.editMode) this.setEditMode(true);
      else pv.buildItems();
      this.select(pv, im, 'image');
      this.changed();
    } catch (err) {
      toast(`Could not add that picture: ${err.message}`);
    }
  }

  // ---------- inspector ----------

  renderInspector() {
    clear(this.inspector);
    const sel = this.selected;
    if (!sel || !this.editMode) {
      this.inspector.hidden = true;
      return;
    }
    this.inspector.hidden = false;
    const { pv, model: o, type } = sel;
    const rebuild = () => {
      pv.buildItems();
      this.changed();
      this.renderInspector();
    };
    const row = [];
    const label = (text, control) => h('label', { class: 'field' }, text, control);
    const colour = (key, text = 'Colour') =>
      label(text, h('input', { type: 'color', value: o[key] || '#FFE98A', onInput: (e) => { o[key] = e.target.value; rebuild(); } }));
    const size = () =>
      label('Size', h('input', { type: 'number', min: '10', max: '72', step: '2', value: String(o.fontSize), onChange: (e) => { o.fontSize = clamp(Number(e.target.value) || 18, 10, 72); rebuild(); } }));
    const button = (text, fn) => h('button', { class: 'btn small', text, onClick: fn });

    row.push(h('strong', { text: type === 'image' ? 'Picture' : { text: 'Text box', sticky: 'Sticky note', checklist: 'Checklist', table: 'Table', stamp: 'Stamp' }[o.kind] }));

    if (type === 'object') {
      if (o.kind === 'text') {
        row.push(
          label('Font', h('select', { onChange: (e) => { o.design = e.target.value; rebuild(); } },
            DESIGNS.map(([v, t]) => h('option', { value: v, text: t, selected: o.design === v })))),
          size(),
          h('button', { class: `btn small${o.bold ? ' on' : ''}`, 'aria-pressed': String(o.bold), text: 'B', title: 'Bold', onClick: () => { o.bold = !o.bold; rebuild(); } }),
          h('button', { class: `btn small${o.italic ? ' on' : ''}`, 'aria-pressed': String(o.italic), text: 'I', title: 'Italic', onClick: () => { o.italic = !o.italic; rebuild(); } }),
          label('List', h('select', { onChange: (e) => { o.list = e.target.value; this.changed(); } },
            LISTS.map(([v, t]) => h('option', { value: v, text: t, selected: o.list === v })))),
          colour('colorHex'),
        );
      } else if (o.kind === 'sticky') {
        row.push(colour('fillHex', 'Paper'), colour('colorHex', 'Text'), size());
      } else if (o.kind === 'checklist') {
        row.push(
          colour('colorHex'), size(),
          button('Add item', () => { o.items.push({ id: uuid(), text: '', done: false }); rebuild(); }),
          button('Remove last', () => { if (o.items.length) o.items.pop(); rebuild(); }),
        );
      } else if (o.kind === 'table') {
        row.push(
          colour('colorHex'), size(),
          button('+ Row', () => { o.cells.push(new Array(o.cells[0]?.length || 3).fill('')); rebuild(); }),
          button('− Row', () => { if (o.cells.length > 1) o.cells.pop(); rebuild(); }),
          button('+ Column', () => { o.cells = o.cells.map((r) => [...r, '']); rebuild(); }),
          button('− Column', () => { if ((o.cells[0]?.length || 0) > 1) o.cells = o.cells.map((r) => r.slice(0, -1)); rebuild(); }),
        );
      } else if (o.kind === 'stamp') {
        row.push(
          label('Text', h('input', { type: 'text', value: o.text, maxlength: '30', onInput: (e) => { o.text = e.target.value; this.changed(); }, onChange: rebuild })),
          colour('colorHex'), size(),
        );
      }
    }

    const list = type === 'image' ? pv.page.images : pv.page.objects;
    row.push(
      button('Duplicate', () => {
        const copy = JSON.parse(JSON.stringify(o));
        copy.id = uuid();
        copy.x += 24;
        copy.y += 24;
        if (copy.items) for (const it of copy.items) it.id = uuid();
        list.push(copy);
        pv.buildItems();
        this.select(pv, copy, type);
        this.changed();
      }),
      h('button', {
        class: 'btn small danger', text: 'Delete',
        onClick: () => {
          list.splice(list.indexOf(o), 1);
          this.select(null);
          pv.buildItems();
          this.changed();
        },
      }),
    );
    this.inspector.append(...row);
  }

  // ---------- menus and export ----------

  pagesMenu(anchor) {
    const at = this.views.indexOf(this.activeView());
    popMenu(anchor, [
      { label: `Add page after page ${at + 1}`, onClick: () => this.addPage() },
      { label: 'Duplicate this page', onClick: () => this.duplicatePage() },
      { label: 'Move page up', disabled: at === 0, onClick: () => this.movePage(-1) },
      { label: 'Move page down', disabled: at === this.views.length - 1, onClick: () => this.movePage(1) },
      { label: 'Delete this page', danger: true, onClick: () => this.deletePage() },
      { divider: true },
      { label: `Template: ${templateTitle(this.note.template)}`, disabled: true },
      ...TEMPLATES.map((t) => ({ label: `  ${t.title}`, onClick: () => this.changeTemplate(t.id) })),
    ]);
  }

  exportMenu(anchor) {
    popMenu(anchor, [
      { label: 'Download this page as a picture (PNG)', onClick: () => this.exportPng() },
      { label: 'Print or save as PDF…', onClick: () => this.exportPdf() },
    ]);
  }

  async loadAllImages(pages) {
    const jobs = [];
    for (const p of pages) {
      if (p.background) jobs.push(this.lib.loadImage(p.background));
      for (const im of p.images || []) jobs.push(this.lib.loadImage(im.file, im.mime || 'image/jpeg'));
    }
    await Promise.allSettled(jobs);
  }

  async exportPng() {
    const pv = this.activeView();
    await this.loadAllImages([pv.page]);
    const canvas = flattenPage(pv.page, this.note.template, this.lib.images, 2);
    const at = this.views.indexOf(pv) + 1;
    canvas.toBlob((blob) => download(blob, `${safeFilename(this.note.title)} page ${at}.png`), 'image/png');
  }

  async exportPdf() {
    await this.loadAllImages(this.note.pages);
    const root = h('div', { id: 'print-root' });
    for (const page of this.note.pages) {
      const canvas = flattenPage(page, this.note.template, this.lib.images, 2);
      root.append(h('img', { src: canvas.toDataURL('image/jpeg', 0.92), alt: '' }));
    }
    document.body.append(root);
    document.body.classList.add('printing');
    const cleanup = () => {
      root.remove();
      document.body.classList.remove('printing');
      window.removeEventListener('afterprint', cleanup);
    };
    window.addEventListener('afterprint', cleanup);
    setTimeout(() => window.print(), 100);
  }
}
