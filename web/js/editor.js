// The note editor: pages with pen, highlighter and eraser, plus text boxes, sticky notes,
// checklists, tables, stamps and pictures that can be moved and resized in "edit objects" mode.

import { h, clear, toast, popMenu, modal, download, safeFilename } from './dom.js';
import { PAGE_W, PAGE_H, TEMPLATES, WHITEBOARD_BACKGROUNDS, templateTitle } from './templates.js';
import {
  drawPaper, drawInk, drawStroke, distanceToStroke, flattenPage, pageSpec, objectFont, rowHeight, layoutHeight,
  SHAPE_KINDS, BORDERS, shapePath,
} from './render.js';
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

const KIND_NAMES = {
  text: 'Text box', sticky: 'Sticky note', checklist: 'Checklist', table: 'Table', stamp: 'Stamp',
  line: 'Line', arrow: 'Arrow', rectangle: 'Rectangle', ellipse: 'Circle', triangle: 'Triangle', star: 'Star',
};
const WATERMARK_COLOURS = [['Grey', '#8C99B3'], ['Red', '#C0392B'], ['Blue', '#2F5BEA'], ['Green', '#2E8B57'], ['Black', '#1B2430']];
const WATERMARK_PICKS = ['DRAFT', 'CONFIDENTIAL', 'COPY', 'SAMPLE', 'DO NOT COPY', 'FOR REVIEW'];
const SVG_NS = 'http://www.w3.org/2000/svg';

/** Shapes and stamps have no text field in the way, so they can be dragged from anywhere on them. */
const movableByBody = (o) => SHAPE_KINDS.includes(o.kind) || o.kind === 'stamp';

/** New object with the same fields the iPad app uses. */
export function makeObject(kind, text = '') {
  const o = {
    id: uuid(), kind, x: 80, y: 160, width: 220, height: 120,
    colorHex: '#1B2430', fillHex: null, lineWidth: 3, text: '', fontSize: 18,
    design: 'sans', bold: false, italic: false, list: 'none', items: [], cells: [],
    rotation: 0, opacity: 1, border: 'rounded',
  };
  switch (kind) {
    case 'line':
    case 'arrow':
      o.width = 240; o.height = 30;
      break;
    case 'triangle':
      o.width = 180; o.height = 150;
      break;
    case 'star':
      o.width = 160; o.height = 160; o.fillHex = '#FFD84D';
      break;
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

/** A page object from a saved custom stamp. Sized to its words, the same way the iPad does it. */
export function stampObject(saved) {
  const o = makeObject('stamp', saved.text);
  Object.assign(o, {
    colorHex: saved.colorHex, fontSize: saved.fontSize, bold: saved.bold, border: saved.border,
    rotation: saved.rotation, opacity: saved.opacity,
  });
  const lines = String(saved.text).split('\n');
  const longest = Math.max(1, ...lines.map((l) => l.length));
  o.width = Math.max(110, longest * saved.fontSize * 0.62 + 44);
  o.height = Math.max(48, lines.length * saved.fontSize * 1.3 + 26);
  return o;
}

/** The look of a stamp on the page, saved so it can be reused. */
const stampFromObject = (o) => ({
  name: (o.text || '').replace(/\n/g, ' ').trim() || 'My stamp', text: o.text || '', colorHex: o.colorHex,
  fontSize: o.fontSize, bold: !!o.bold, border: o.border || 'rounded', rotation: o.rotation || 0, opacity: o.opacity ?? 1,
});

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

  /** This note's page size in points. Every page of a note is the same size. */
  get pw() {
    return this.editor.note.pageWidth || PAGE_W;
  }

  get ph() {
    return this.editor.note.pageHeight || PAGE_H;
  }

  get spec() {
    return pageSpec(this.editor.note, this.editor.views.indexOf(this));
  }

  applySize(scale) {
    const { pw, ph } = this;
    // The layout is re-checked whenever the screen's size changes (even when the editing bar appears).
    // If nothing about this page's size changed, leave it alone so objects being dragged aren't rebuilt.
    if (this.sized && Math.abs(scale - this.scale) < 0.0001 && this.sized.pw === pw && this.sized.ph === ph) return;
    this.sized = { pw, ph };
    this.scale = scale;
    this.el.style.width = `${Math.round(pw * scale)}px`;
    this.el.style.height = `${Math.round(ph * scale)}px`;
    this.scaler.style.width = `${pw}px`;
    this.scaler.style.height = `${ph}px`;
    for (const c of [this.paper, this.ink, this.live]) {
      c.style.width = `${pw}px`;
      c.style.height = `${ph}px`;
    }
    this.scaler.style.transform = `scale(${scale})`;
    if (this.rendered) this.render();
  }

  ctx(canvas) {
    const x = canvas.getContext('2d');
    x.setTransform(this.k, 0, 0, this.k, 0, 0);
    return x;
  }

  render() {
    const { pw, ph } = this;
    // Big whiteboards would need enormous bitmaps; keep each canvas to about 8 million pixels.
    const cap = Math.min(3, Math.sqrt(8e6 / (pw * ph)));
    this.k = clamp((window.devicePixelRatio || 1) * this.scale, 0.25, cap);
    for (const c of [this.paper, this.ink, this.live]) {
      c.width = Math.max(1, Math.round(pw * this.k));
      c.height = Math.max(1, Math.round(ph * this.k));
    }
    this.rendered = true;
    this.redrawPaper();
    this.redrawInk();
    // Objects are positioned in page units, so a new canvas size doesn't move them: keep what's there.
    if (!this.items.childElementCount) this.buildItems();
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
    x.clearRect(0, 0, this.pw, this.ph);
    drawPaper(x, this.page, this.spec, this.editor.lib.images, { objects: !edit, pictures: !edit });
  }

  redrawInk() {
    if (!this.rendered) return;
    const x = this.ctx(this.ink);
    x.clearRect(0, 0, this.pw, this.ph);
    drawInk(x, this.page);
  }

  redrawLive(stroke) {
    const x = this.ctx(this.live);
    x.clearRect(0, 0, this.pw, this.ph);
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
        model.x = clamp(ox + dx, -model.width + 30, this.pw - 30);
        model.y = clamp(oy + dy, -20, this.ph - 30);
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
      // A resized shape is redrawn at its new size so its outline stays crisp.
      if (mode === 'resize' && SHAPE_KINDS.includes(model.kind)) this.buildItems();
    };
    target.addEventListener('pointermove', move);
    target.addEventListener('pointerup', up);
    target.addEventListener('pointercancel', up);
  }

  handles(el, model, type, opts) {
    return [
      h('div', { class: 'handle move', title: 'Drag to move', onPointerdown: (e) => this.startDrag(e, 'move', el, model) }, '✥'),
      h('div', { class: 'handle resize', title: 'Drag to resize', onPointerdown: (e) => this.startDrag(e, 'resize', el, model, opts) }, '⤡'),
      h('button', {
        class: 'handle del', title: 'Delete (Delete key)', 'aria-label': 'Delete', text: '×',
        onPointerdown: (e) => e.stopPropagation(),
        onClick: () => this.editor.deleteItem(this, model, type),
      }),
    ];
  }

  /** Tilt and see-through, applied to the item on screen. The handles are left upright. */
  styleItem(el, model) {
    el.style.transform = model.rotation ? `rotate(${model.rotation}deg)` : '';
    const body = el.firstElementChild;
    if (body) body.style.opacity = model.opacity != null && model.opacity < 1 ? String(model.opacity) : '';
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
    } else if (SHAPE_KINDS.includes(o.kind)) {
      // One <svg> whose path is the same one the canvas draws, so the page and the editor match.
      const svg = document.createElementNS(SVG_NS, 'svg');
      svg.setAttribute('viewBox', `0 0 ${o.width} ${o.height}`);
      svg.setAttribute('preserveAspectRatio', 'none');
      svg.setAttribute('class', 'shape');
      const path = document.createElementNS(SVG_NS, 'path');
      path.setAttribute('d', shapePath(o.kind, o.width, o.height));
      path.setAttribute('fill', o.fillHex && o.kind !== 'line' && o.kind !== 'arrow' ? o.fillHex : 'none');
      path.setAttribute('stroke', o.colorHex);
      path.setAttribute('stroke-width', String(o.lineWidth || 3));
      path.setAttribute('stroke-linecap', 'round');
      path.setAttribute('stroke-linejoin', 'round');
      path.setAttribute('vector-effect', 'non-scaling-stroke');
      svg.append(path);
      body = svg;
    } else {
      body = h('div', {
        class: `stamp ${o.border || 'rounded'}`,
        style: { color: o.colorHex, borderColor: o.colorHex, font: objectFont(o) },
        text: (o.text || '').toUpperCase(),
      });
    }
    el.append(body, ...this.handles(el, o, 'object', { resizeHeight: o.kind === 'sticky' || o.kind === 'stamp' || SHAPE_KINDS.includes(o.kind) }));
    if (movableByBody(o)) {
      body.addEventListener('pointerdown', (e) => {
        ed.select(this, o, 'object');
        this.startDrag(e, 'move', el, o);
      });
    }
    el.addEventListener('pointerdown', () => ed.select(this, o, 'object'), true);
    this.styleItem(el, o);
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
    this.zoom = null;      // whiteboards only: null means "fit the whole board"
    this.boardFit = 1;
    this.lastDeleted = null;   // the object just deleted, so "Undo" can put it back

    this.build();
    this.renderPages();
    // Ctrl or Cmd with the wheel (and a trackpad pinch) zooms a whiteboard.
    this.scroller.addEventListener('wheel', (e) => {
      if (!this.isBoard || !(e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      this.zoomBy(e.deltaY < 0 ? 1.1 : 0.9);
    }, { passive: false });

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

  get isBoard() {
    return this.note.kind === 'whiteboard';
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
    this.zoomBox = h('div', { class: 'zoom', hidden: !this.isBoard },
      h('button', { class: 'icon', title: 'Zoom out', 'aria-label': 'Zoom out', text: '−', onClick: () => this.zoomBy(0.8) }),
      h('button', { class: 'btn small', title: 'Fit the whole whiteboard', text: 'Fit', onClick: () => this.zoomFit() }),
      h('button', { class: 'icon', title: 'Zoom in', 'aria-label': 'Zoom in', text: '+', onClick: () => this.zoomBy(1.25) }));
    const pagesBtn = h('button', { class: 'btn', text: this.isBoard ? 'Board ▾' : 'Pages ▾' });
    pagesBtn.addEventListener('click', () => this.pagesMenu(pagesBtn));
    const exportBtn = h('button', { class: 'btn primary', text: 'Export ▾' });
    exportBtn.addEventListener('click', () => this.exportMenu(exportBtn));

    this.fileInput = h('input', { type: 'file', accept: 'image/*', hidden: true, onChange: () => this.pickedPicture(this.fileInput) });
    this.cameraInput = h('input', {
      type: 'file', accept: 'image/*', capture: 'environment', hidden: true, onChange: () => this.pickedPicture(this.cameraInput),
    });

    this.inspector = h('div', { class: 'ed-inspector', hidden: true });
    this.pagesEl = h('div', { class: `ed-pages${this.isBoard ? ' board' : ''}` });
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
            this.titleInput, this.statusEl, this.undoBtn, this.redoBtn, this.zoomBox, insertBtn, this.editBtn, pagesBtn, exportBtn),
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
    const availW = Math.max(260, this.scroller.clientWidth - 24);
    const availH = Math.max(200, this.scroller.clientHeight - 24);
    const pw = this.note.pageWidth || PAGE_W;
    const ph = this.note.pageHeight || PAGE_H;
    this.boardFit = Math.min(1, availW / pw, availH / ph);
    // A page fits the screen's width. A whole whiteboard fits on screen until you zoom.
    const scale = this.isBoard ? this.zoom ?? this.boardFit : Math.min(availW / pw, 1.4);
    for (const pv of this.views) pv.applySize(scale);
  }

  zoomBy(factor) {
    this.zoom = clamp((this.zoom ?? this.boardFit) * factor, 0.08, 4);
    this.layout();
  }

  zoomFit() {
    this.zoom = null;
    this.layout();
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
    return [((e.clientX - r.left) * pv.pw) / r.width, ((e.clientY - r.top) * pv.ph) / r.height];
  }

  pointerDown(e, pv) {
    if (this.editMode) return;
    if (e.pointerType === 'touch' && this.penOnly) {
      // The finger scrolls instead of drawing; the canvas can't do this itself because it needs touch-action: none for the pen.
      this.panning = {
        id: e.pointerId, x: e.clientX, y: e.clientY, left: this.scroller.scrollLeft, top: this.scroller.scrollTop,
      };
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
      this.scroller.scrollLeft = this.panning.left - (e.clientX - this.panning.x);   // whiteboards scroll sideways too
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
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)) return;
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      if (e.shiftKey) this.redo();
      else this.undo();
      return;
    }
    // With something selected in edit mode: Delete removes it, the arrow keys nudge it (Shift for bigger steps).
    const sel = this.selected;
    if (!this.editMode || !sel) return;
    if (e.key === 'Delete' || e.key === 'Backspace') {
      e.preventDefault();
      this.deleteItem(sel.pv, sel.model, sel.type);
      return;
    }
    const step = e.shiftKey ? 10 : 1;
    const move = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[e.key];
    if (move) {
      e.preventDefault();
      sel.model.x += move[0];
      sel.model.y += move[1];
      const el = sel.pv.items.querySelector(`.item[data-id="${sel.model.id}"]`);
      if (el) {
        el.style.left = `${sel.model.x}px`;
        el.style.top = `${sel.model.y}px`;
      }
      this.changed();
    }
  }

  /** Removes a selected object or picture. A message offers Undo for a few seconds. */
  deleteItem(pv, model, type) {
    const list = type === 'image' ? pv.page.images : pv.page.objects;
    const index = list.indexOf(model);
    if (index < 0) return;
    list.splice(index, 1);
    this.lastDeleted = { pageId: pv.page.id, type, index, model };
    this.select(null);
    pv.buildItems();
    this.changed();
    const name = type === 'image' ? 'Picture' : KIND_NAMES[model.kind] || 'Item';
    toast(`${name} deleted`, 8000, { label: 'Undo', onClick: () => this.restoreDeleted() });
  }

  restoreDeleted() {
    const gone = this.lastDeleted;
    if (!gone) return;
    const pv = this.views.find((v) => v.page.id === gone.pageId);
    if (!pv) return;
    const list = gone.type === 'image' ? pv.page.images : pv.page.objects;
    list.splice(Math.min(gone.index, list.length), 0, gone.model);
    this.lastDeleted = null;
    if (!pv.rendered) pv.render();
    if (!this.editMode) this.setEditMode(true);
    else pv.buildItems();
    this.select(pv, gone.model, gone.type);
    this.changed();
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
    const today = new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
    popMenu(anchor, [
      { label: 'Text box', onClick: () => this.insertObject('text') },
      { label: 'Sticky note', onClick: () => this.insertObject('sticky') },
      { label: 'Checklist', onClick: () => this.insertObject('checklist') },
      { label: 'Table', onClick: () => this.insertObject('table') },
      { divider: true },
      { label: 'Shapes', disabled: true },
      ...SHAPE_KINDS.map((k) => ({ label: `  ${KIND_NAMES[k]}`, onClick: () => this.insertObject(k) })),
      { divider: true },
      { label: 'Stamps', disabled: true },
      ...STAMPS.map((s) => ({ label: `  ${s}`, onClick: () => this.insertObject('stamp', s) })),
      { label: `  ${today}`, onClick: () => this.insertObject('stamp', today) },
      ...this.lib.stamps.slice(0, 8).map((s) => ({ label: `  ★ ${s.name}`, onClick: () => this.placeObject(stampObject(s)) })),
      { label: '  My stamps…', onClick: () => this.openStampLibrary() },
      { label: '  Make a custom stamp…', onClick: () => this.openStampEditor(null, null, true) },
      { divider: true },
      { label: 'Picture from this device…', onClick: () => this.fileInput.click() },
      { label: 'Take a photo…', onClick: () => this.cameraInput.click() },
    ]);
  }

  insertObject(kind, text = '') {
    this.placeObject(makeObject(kind, text));
  }

  /** Puts a ready-made object on the page being looked at, and selects it. */
  placeObject(o) {
    const pv = this.activeView();
    if (!pv.rendered) pv.render();
    const offset = (pv.page.objects.length % 8) * 36;
    // Keep objects inside small pages (A6 is only 397 points wide). Whiteboards are huge, so start in the middle.
    o.width = Math.min(o.width, Math.max(80, pv.pw - 80));
    if (this.isBoard) {
      o.x = (pv.pw - o.width) / 2 + offset;
      o.y = pv.ph / 2 - 60 + offset;
    } else {
      o.x = Math.min(o.x + offset, Math.max(20, pv.pw - o.width - 20));
      o.y = Math.min(o.y + offset, Math.max(20, pv.ph - 200));
    }
    pv.page.objects.push(o);
    if (!this.editMode) this.setEditMode(true);
    else pv.buildItems();
    this.select(pv, o, 'object');
    this.changed();
    const el = pv.items.querySelector(`.item[data-id="${o.id}"]`);
    if (this.isBoard) el?.scrollIntoView({ block: 'center', inline: 'center' });
    el?.querySelector('textarea')?.focus();
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
      const w = Math.min(320, pv.pw * 0.6, bitmap.width);
      const height = (w * bitmap.height) / bitmap.width;
      const im = {
        id: uuid(), file: fileId, mime: 'image/jpeg',
        x: (pv.pw - w) / 2, y: this.isBoard ? (pv.ph - height) / 2 : Math.min(200, pv.ph * 0.15),
        width: w, height,
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

  // ---------- custom stamps ----------

  stampPreview(s) {
    return h('span', {
      class: `stamp-mini ${s.border || 'rounded'}`,
      style: {
        color: s.colorHex, borderColor: s.colorHex, opacity: String(s.opacity ?? 1), transform: `rotate(${s.rotation || 0}deg)`,
        font: `${s.bold ? 'bold ' : ''}${Math.min(s.fontSize || 22, 22)}px -apple-system, Helvetica, Arial, sans-serif`,
      },
      text: (s.text || '').toUpperCase(),
    });
  }

  /** "My stamps": tap one to place it, make new ones, edit or delete old ones. */
  openStampLibrary() {
    const list = h('div', { class: 'stamp-list' });
    let closeDialog = () => {};
    const render = () => {
      clear(list);
      if (!this.lib.stamps.length) {
        list.append(h('p', { class: 'hint', text: 'No saved stamps yet. Make one, or select a stamp on a page and choose "Save to my stamps".' }));
      }
      for (const s of this.lib.stamps) {
        list.append(h('div', { class: 'stamp-row' },
          h('button', { class: 'stamp-use', title: 'Place on the page', onClick: () => { closeDialog(); this.placeObject(stampObject(s)); } },
            this.stampPreview(s), h('span', { class: 'stamp-name', text: s.name })),
          h('button', { class: 'btn small', text: 'Edit', onClick: () => this.openStampEditor(s, render, false) }),
          h('button', { class: 'btn small danger', text: 'Delete', onClick: () => { this.lib.deleteStamp(s.id); render(); } })));
      }
    };
    closeDialog = modal('My stamps', (close) => {
      render();
      return h('div', { class: 'stack' }, list,
        h('div', { class: 'row-btns end' },
          h('button', { class: 'btn', text: 'Make a stamp', onClick: () => this.openStampEditor(null, render, false) }),
          h('button', { class: 'btn primary', text: 'Done', onClick: close })));
    });
  }

  /** Make or change a custom stamp. `insert` places it on the page straight after saving. */
  openStampEditor(existing, onSaved, insert = false) {
    const draft = existing ? { ...existing } : {
      id: uuid(), name: '', text: 'PAID', colorHex: '#C0392B', fontSize: 26, bold: true, border: 'rounded', rotation: -8, opacity: 1,
    };
    const previewBox = h('div', { class: 'stamp-preview' });
    const redraw = () => {
      clear(previewBox);
      previewBox.append(this.stampPreview({ ...draft, fontSize: Math.min(draft.fontSize, 34) }));
    };
    const textArea = h('textarea', { rows: '2', maxlength: '60', value: draft.text, onInput: () => { draft.text = textArea.value; redraw(); } });
    const nameInput = h('input', { type: 'text', value: draft.name, maxlength: '40', onInput: () => { draft.name = nameInput.value; } });
    const colour = h('input', { type: 'color', value: draft.colorHex, onInput: (e) => { draft.colorHex = e.target.value; redraw(); } });
    const sizeInput = h('input', { type: 'number', min: '12', max: '72', step: '2', value: String(draft.fontSize), onInput: (e) => { draft.fontSize = clamp(Number(e.target.value) || 26, 12, 72); redraw(); } });
    const bold = h('input', { type: 'checkbox', checked: draft.bold, onChange: (e) => { draft.bold = e.target.checked; redraw(); } });
    const border = h('select', { onChange: (e) => { draft.border = e.target.value; redraw(); } },
      BORDERS.map(([v, t]) => h('option', { value: v, text: t, selected: draft.border === v })));
    const slider = (key, min, max, step, fmt) => {
      const out = h('span', { class: 'range-val', text: fmt(draft[key]) });
      const input = h('input', { type: 'range', min, max, step, value: String(draft[key]), onInput: (e) => { draft[key] = Number(e.target.value); out.textContent = fmt(draft[key]); redraw(); } });
      return h('span', { class: 'range-row' }, input, out);
    };
    const field = (t, c) => h('label', { class: 'field' }, t, c);
    redraw();
    modal(existing ? 'Edit stamp' : 'Make a stamp', (close) =>
      h('div', { class: 'stack' }, previewBox,
        field('Stamp text', textArea), field('Name in your list (optional)', nameInput),
        h('div', { class: 'row-btns' }, field('Colour', colour), field('Text size', sizeInput), h('label', { class: 'check' }, bold, 'Bold')),
        field('Border', border),
        field('Tilt', slider('rotation', -45, 45, 1, (v) => `${v}°`)),
        field('Opacity', slider('opacity', 0.1, 1, 0.05, (v) => `${Math.round(v * 100)}%`)),
        h('div', { class: 'row-btns end' },
          h('button', { class: 'btn', text: 'Cancel', onClick: close }),
          h('button', { class: 'btn primary', text: 'Save stamp', onClick: () => {
            if (!draft.text.trim()) return toast('Type the words for the stamp first.');
            if (!draft.name.trim()) draft.name = draft.text.replace(/\n/g, ' ').trim();
            const saved = this.lib.saveStamp(draft);
            close();
            onSaved?.(saved);
            if (insert) this.placeObject(stampObject(saved));
          } }))));
  }

  // ---------- watermark ----------

  /** A watermark across every page of the note: behind the writing, and in exports and printouts. */
  openWatermark() {
    const current = this.note.watermark;
    const wm = {
      text: current?.text ?? 'DRAFT', colorHex: current?.colorHex ?? '#8C99B3', opacity: current?.opacity ?? 0.18,
      angle: current?.angle ?? -35, size: current?.size ?? 120, border: current?.border ?? 'rounded', tiled: current?.tiled ?? false,
    };
    let on = true;   // opening this screen means you want one; untick the box to remove it
    const preview = h('canvas', { class: 'nb-preview', 'aria-hidden': 'true' });
    const redraw = () => {
      const base = pageSpec(this.note, 0);
      const k = Math.min(240 / base.w, 320 / base.h);
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      preview.width = Math.max(1, Math.round(base.w * k * dpr));
      preview.height = Math.max(1, Math.round(base.h * k * dpr));
      preview.style.width = `${Math.round(base.w * k)}px`;
      preview.style.height = `${Math.round(base.h * k)}px`;
      const ctx = preview.getContext('2d');
      ctx.setTransform(k * dpr, 0, 0, k * dpr, 0, 0);
      drawPaper(ctx, {}, { ...base, watermark: on && wm.text.trim() ? { ...wm } : null }, new Map());
    };
    const field = (t, c) => h('label', { class: 'field' }, t, c);
    const slider = (key, min, max, step, fmt) => {
      const out = h('span', { class: 'range-val', text: fmt(wm[key]) });
      const input = h('input', { type: 'range', min, max, step, value: String(wm[key]), onInput: (e) => { wm[key] = Number(e.target.value); out.textContent = fmt(wm[key]); redraw(); } });
      return h('span', { class: 'range-row' }, input, out);
    };
    const onBox = h('input', { type: 'checkbox', checked: on, onChange: () => { on = onBox.checked; redraw(); } });
    const textInput = h('input', { type: 'text', value: wm.text, maxlength: '40', onInput: () => { wm.text = textInput.value; redraw(); } });
    const swatches = h('div', { class: 'swatch-row' });
    const renderSwatches = () => {
      clear(swatches);
      for (const [name, hex] of WATERMARK_COLOURS) {
        swatches.append(h('button', { type: 'button', class: `sw${wm.colorHex === hex ? ' on' : ''}`, style: { background: hex }, title: name, 'aria-label': name, onClick: () => { wm.colorHex = hex; renderSwatches(); redraw(); } }));
      }
    };
    const border = h('select', { onChange: (e) => { wm.border = e.target.value; redraw(); } },
      BORDERS.map(([v, t]) => h('option', { value: v, text: t, selected: wm.border === v })));
    const tiled = h('input', { type: 'checkbox', checked: wm.tiled, onChange: () => { wm.tiled = tiled.checked; redraw(); } });
    renderSwatches();
    redraw();
    modal('Watermark', (close) =>
      h('div', { class: 'setup' },
        h('div', { class: 'setup-form stack' },
          h('label', { class: 'check' }, onBox, 'Show a watermark on every page'),
          field('Text', textInput),
          h('div', { class: 'row-btns' }, WATERMARK_PICKS.map((p) => h('button', { type: 'button', class: 'btn small', text: p, onClick: () => { wm.text = p; textInput.value = p; redraw(); } }))),
          field('Colour', swatches),
          field('Border (makes it look like a stamp)', border),
          field('Strength', slider('opacity', 0.05, 0.6, 0.01, (v) => `${Math.round(v * 100)}%`)),
          field('Angle', slider('angle', -90, 90, 1, (v) => `${v}°`)),
          field('Size', slider('size', 30, 300, 5, (v) => String(v))),
          h('label', { class: 'check' }, tiled, 'Repeat across the page'),
          h('div', { class: 'row-btns end' },
            h('button', { class: 'btn', text: 'Cancel', onClick: close }),
            h('button', { class: 'btn primary', text: 'Apply', onClick: () => {
              if (on && wm.text.trim()) this.note.watermark = { ...wm, text: wm.text.trim() };
              else delete this.note.watermark;
              this.changed();
              for (const pv of this.views) pv.redrawPaper();
              close();
            } }))),
        h('div', { class: 'setup-preview' }, h('div', { class: 'nb-wrap' }, preview))),
    { wide: true });
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
    // Tilt and opacity update the item on screen as the slider moves, without rebuilding it.
    const range = (text, key, min, max, step, fmt) => {
      const out = h('span', { class: 'range-val', text: fmt(o[key] ?? (key === 'opacity' ? 1 : 0)) });
      const input = h('input', {
        type: 'range', min, max, step, value: String(o[key] ?? (key === 'opacity' ? 1 : 0)), 'aria-label': text,
        onInput: (e) => {
          o[key] = Number(e.target.value);
          out.textContent = fmt(o[key]);
          const el = pv.items.querySelector(`.item[data-id="${o.id}"]`);
          if (el) pv.styleItem(el, o);
          this.changed();
        },
      });
      return h('label', { class: 'field' }, text, h('span', { class: 'range-row' }, input, out));
    };
    const tilt = () => range('Tilt', 'rotation', -180, 180, 1, (v) => `${v}°`);
    const opacity = () => range('Opacity', 'opacity', 0.1, 1, 0.05, (v) => `${Math.round(v * 100)}%`);

    row.push(h('strong', { text: type === 'image' ? 'Picture' : KIND_NAMES[o.kind] || 'Object' }));

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
        row.push(colour('fillHex', 'Paper'), colour('colorHex', 'Text'), size(), tilt());
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
          label('Text', h('textarea', { rows: '2', maxlength: '60', value: o.text, onInput: (e) => { o.text = e.target.value; this.changed(); }, onChange: rebuild })),
          colour('colorHex'), size(),
          h('button', { class: `btn small${o.bold ? ' on' : ''}`, 'aria-pressed': String(!!o.bold), text: 'B', title: 'Bold', onClick: () => { o.bold = !o.bold; rebuild(); } }),
          label('Border', h('select', { onChange: (e) => { o.border = e.target.value; rebuild(); } },
            BORDERS.map(([v, t]) => h('option', { value: v, text: t, selected: (o.border || 'rounded') === v })))),
          tilt(), opacity(),
          button('Save to my stamps', () => {
            this.lib.saveStamp(stampFromObject(o));
            toast('Saved to My stamps. Use it again from Insert, then My stamps.');
          }),
        );
      } else if (SHAPE_KINDS.includes(o.kind)) {
        const fillable = o.kind !== 'line' && o.kind !== 'arrow';
        row.push(
          colour('colorHex', 'Line'),
          label('Width', h('input', { type: 'number', min: '1', max: '14', step: '1', value: String(o.lineWidth || 3), onChange: (e) => { o.lineWidth = clamp(Number(e.target.value) || 3, 1, 14); rebuild(); } })),
          ...(fillable ? [
            h('label', { class: 'check' }, h('input', { type: 'checkbox', checked: !!o.fillHex, onChange: (e) => { o.fillHex = e.target.checked ? (o.fillHex || '#BFD3FF') : null; rebuild(); } }), 'Fill'),
            o.fillHex ? colour('fillHex', 'Fill colour') : null,
          ] : []),
          tilt(), opacity(),
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
      h('button', { class: 'btn small danger', text: 'Delete', onClick: () => this.deleteItem(pv, o, type) }),
    );
    this.inspector.append(...row.filter(Boolean));
  }

  // ---------- menus and export ----------

  pagesMenu(anchor) {
    if (this.isBoard) {
      popMenu(anchor, [
        { label: 'Zoom to fit the whole board', onClick: () => this.zoomFit() },
        { label: 'Zoom to 100%', onClick: () => { this.zoom = 1; this.layout(); } },
        { divider: true },
        { label: `Background: ${templateTitle(this.note.template)}`, disabled: true },
        ...WHITEBOARD_BACKGROUNDS.map((id) => ({ label: `  ${templateTitle(id)}`, onClick: () => this.changeTemplate(id) })),
      ]);
      return;
    }
    const at = this.views.indexOf(this.activeView());
    popMenu(anchor, [
      { label: `Add page after page ${at + 1}`, onClick: () => this.addPage() },
      { label: 'Duplicate this page', onClick: () => this.duplicatePage() },
      { label: 'Move page up', disabled: at === 0, onClick: () => this.movePage(-1) },
      { label: 'Move page down', disabled: at === this.views.length - 1, onClick: () => this.movePage(1) },
      { label: 'Delete this page', danger: true, onClick: () => this.deletePage() },
      { divider: true },
      { label: this.note.pageNumbers ? 'Hide page numbers' : 'Show page numbers', onClick: () => this.togglePageNumbers() },
      { label: this.note.watermark ? 'Edit watermark…' : 'Add watermark…', onClick: () => this.openWatermark() },
      { divider: true },
      { label: `Template: ${templateTitle(this.note.template)}`, disabled: true },
      ...TEMPLATES.map((t) => ({ label: `  ${t.title}`, onClick: () => this.changeTemplate(t.id) })),
    ]);
  }

  togglePageNumbers() {
    this.note.pageNumbers = !this.note.pageNumbers;
    this.changed();
    for (const pv of this.views) pv.redrawPaper();
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
    const canvas = flattenPage(pv.page, pv.spec, this.lib.images, 2);
    const at = this.views.indexOf(pv) + 1;
    canvas.toBlob((blob) => download(blob, `${safeFilename(this.note.title)} page ${at}.png`), 'image/png');
  }

  async exportPdf() {
    await this.loadAllImages(this.note.pages);
    const root = h('div', { id: 'print-root' });
    this.note.pages.forEach((page, i) => {
      const canvas = flattenPage(page, pageSpec(this.note, i), this.lib.images, 2);
      root.append(h('img', { src: canvas.toDataURL('image/jpeg', 0.92), alt: '' }));
    });
    // Print at the note's own paper size rather than always A4.
    const { pageWidth = PAGE_W, pageHeight = PAGE_H } = this.note;
    const style = h('style', {
      text: `@media print { @page { size: ${pageWidth}px ${pageHeight}px; margin: 0 } body.printing #print-root img { width: ${pageWidth}px; height: ${pageHeight}px } }`,
    });
    document.head.append(style);
    document.body.append(root);
    document.body.classList.add('printing');
    const cleanup = () => {
      root.remove();
      style.remove();
      document.body.classList.remove('printing');
      window.removeEventListener('afterprint', cleanup);
    };
    window.addEventListener('afterprint', cleanup);
    setTimeout(() => window.print(), 100);
  }
}
