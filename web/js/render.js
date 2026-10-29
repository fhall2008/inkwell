// Draws a page (template, pictures, objects, ink) onto a canvas. Shared by the editor, thumbnails and exports.
import { PAGE_W, PAGE_H, drawTemplateFitted, drawBoard } from './templates.js';

const FAMILIES = {
  sans: '-apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif',
  serif: 'ui-serif, Georgia, "Times New Roman", serif',
  rounded: 'ui-rounded, "SF Pro Rounded", system-ui, sans-serif',
  mono: 'ui-monospace, Menlo, Consolas, monospace',
};

export const fontFamily = (o) => FAMILIES[o.design] || FAMILIES.sans;
export const objectFont = (o) => `${o.italic ? 'italic ' : ''}${o.bold ? 'bold ' : ''}${o.fontSize || 18}px ${fontFamily(o)}`;
export const rowHeight = (o) => (o.fontSize || 18) * 1.6 + 8;

/** Text with bullets or numbers added line by line. */
export function formattedText(o) {
  const text = o.text || '';
  const lines = text.split('\n');
  if (o.list === 'bullet') return lines.map((l) => `• ${l}`).join('\n');
  if (o.list === 'numbered') return lines.map((l, i) => `${i + 1}. ${l}`).join('\n');
  return text;
}

/** Height of objects that size themselves from their rows. */
export function layoutHeight(o) {
  if (o.kind === 'checklist') return Math.max(rowHeight(o), (o.items?.length || 0) * rowHeight(o));
  if (o.kind === 'table') return Math.max(rowHeight(o), (o.cells?.length || 0) * rowHeight(o));
  return o.height;
}

export function wrapLines(ctx, text, maxWidth) {
  const out = [];
  for (const paragraph of String(text).split('\n')) {
    if (paragraph === '') {
      out.push('');
      continue;
    }
    let current = '';
    for (const word of paragraph.split(/(\s+)/)) {
      const test = current + word;
      if (current && ctx.measureText(test).width > maxWidth) {
        out.push(current.trimEnd());
        current = word.trimStart();
      } else {
        current = test;
      }
    }
    out.push(current);
  }
  return out;
}

function fillWrapped(ctx, text, x, y, width, o) {
  ctx.font = objectFont(o);
  ctx.textBaseline = 'top';
  const lineHeight = (o.fontSize || 18) * 1.25;
  wrapLines(ctx, text, width).forEach((line, i) => ctx.fillText(line, x, y + i * lineHeight));
}

export function drawObject(ctx, o) {
  const ink = o.colorHex || '#1B2430';
  const size = o.fontSize || 18;
  ctx.save();
  ctx.fillStyle = ink;
  ctx.strokeStyle = ink;

  switch (o.kind) {
    case 'text':
      fillWrapped(ctx, formattedText(o), o.x, o.y, o.width, o);
      break;

    case 'sticky':
      ctx.save();
      ctx.shadowColor = 'rgba(0,0,0,0.18)';
      ctx.shadowBlur = 5;
      ctx.shadowOffsetY = 2;
      ctx.fillStyle = o.fillHex || '#FFE98A';
      ctx.beginPath();
      ctx.roundRect(o.x, o.y, o.width, o.height, 6);
      ctx.fill();
      ctx.restore();
      ctx.fillStyle = ink;
      fillWrapped(ctx, o.text || '', o.x + 12, o.y + 12, o.width - 24, o);
      break;

    case 'checklist': {
      const rh = rowHeight(o);
      (o.items || []).forEach((item, i) => {
        const rowY = o.y + i * rh;
        const by = rowY + (rh - size) / 2;
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.roundRect(o.x, by, size, size, 3);
        ctx.stroke();
        if (item.done) {
          ctx.lineWidth = 2;
          ctx.lineCap = 'round';
          ctx.beginPath();
          ctx.moveTo(o.x + size * 0.22, by + size * 0.5);
          ctx.lineTo(o.x + size * 0.43, by + size * 0.75);
          ctx.lineTo(o.x + size * 0.8, by + size * 0.25);
          ctx.stroke();
        }
        ctx.font = objectFont(o);
        ctx.textBaseline = 'middle';
        const tx = o.x + size + 10;
        const ty = rowY + rh / 2;
        ctx.fillText(item.text || '', tx, ty);
        if (item.done && item.text) {
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(tx, ty);
          ctx.lineTo(tx + ctx.measureText(item.text).width, ty);
          ctx.stroke();
        }
      });
      break;
    }

    case 'table': {
      const rows = o.cells?.length || 0;
      const cols = o.cells?.[0]?.length || 0;
      if (!cols) break;
      const cw = o.width / cols;
      const rh = rowHeight(o);
      ctx.font = objectFont(o);
      ctx.textBaseline = 'middle';
      ctx.lineWidth = 1;
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const x = o.x + c * cw;
          const y = o.y + r * rh;
          ctx.strokeRect(x, y, cw, rh);
          ctx.save();
          ctx.beginPath();
          ctx.rect(x + 2, y, cw - 4, rh);
          ctx.clip();
          ctx.fillText(o.cells[r][c] || '', x + 6, y + rh / 2);
          ctx.restore();
        }
      }
      break;
    }

    case 'stamp':
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.roundRect(o.x + 1.5, o.y + 1.5, o.width - 3, o.height - 3, 8);
      ctx.stroke();
      ctx.font = objectFont(o);
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText((o.text || '').toUpperCase(), o.x + o.width / 2, o.y + o.height / 2);
      break;

    default:
      break; // unknown kinds (for example shapes from older notes) are skipped
  }
  ctx.restore();
}

/** How one page of a note looks: its size, template, paper colour and page number. Notes made before
 *  notebooks and whiteboards existed have none of these fields, and are A4 on white paper. */
export function pageSpec(note, index = 0) {
  const whiteboard = note.kind === 'whiteboard';
  return {
    w: note.pageWidth || PAGE_W,
    h: note.pageHeight || PAGE_H,
    template: note.template,
    paper: note.paper || '#FFFFFF',
    whiteboard,
    numbers: !!note.pageNumbers && !whiteboard,
    number: index + 1,
  };
}

/** Paper, template (or imported page), page number, pictures and objects. `images` maps image id -> loaded image. */
export function drawPaper(ctx, page, spec, images, { objects = true, pictures = true } = {}) {
  ctx.fillStyle = spec.paper;
  ctx.fillRect(0, 0, spec.w, spec.h);
  if (page.background) {
    const bg = images.get(page.background);
    if (bg) ctx.drawImage(bg, 0, 0, spec.w, spec.h);
  } else if (spec.whiteboard) {
    drawBoard(ctx, spec.template, spec.w, spec.h);
  } else {
    drawTemplateFitted(ctx, spec.template, spec.w, spec.h);
  }
  if (spec.numbers) {
    ctx.save();
    ctx.font = '11px -apple-system, Helvetica, Arial, sans-serif';
    ctx.fillStyle = '#5c6673';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillText(String(spec.number), spec.w / 2, spec.h - 18);
    ctx.restore();
  }
  if (pictures) {
    for (const im of page.images || []) {
      const el = images.get(im.file);
      if (el) ctx.drawImage(el, im.x, im.y, im.width, im.height);
    }
  }
  if (objects) for (const o of page.objects || []) drawObject(ctx, o);
}

/** One stroke: points are [x, y, width]. */
export function drawStroke(ctx, s) {
  const pts = s.points;
  if (!pts || !pts.length) return;
  const highlighter = s.ink === 'highlighter' || s.ink === 'marker';
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.strokeStyle = ctx.fillStyle = s.color || '#1B2430';
  if (highlighter) ctx.globalAlpha = s.opacity ?? 0.35;
  else if (s.ink === 'pencil') ctx.globalAlpha = s.opacity ?? 0.85;

  if (pts.length === 1) {
    ctx.beginPath();
    ctx.arc(pts[0][0], pts[0][1], Math.max(0.5, pts[0][2] / 2), 0, Math.PI * 2);
    ctx.fill();
  } else if (highlighter) {
    // One constant-width path so overlapping parts of the same stroke don't darken.
    ctx.lineWidth = Math.max(0.5, pts.reduce((sum, p) => sum + p[2], 0) / pts.length);
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length - 1; i++) {
      ctx.quadraticCurveTo(pts[i][0], pts[i][1], (pts[i][0] + pts[i + 1][0]) / 2, (pts[i][1] + pts[i + 1][1]) / 2);
    }
    ctx.lineTo(pts[pts.length - 1][0], pts[pts.length - 1][1]);
    ctx.stroke();
  } else {
    let last = [pts[0][0], pts[0][1]];
    for (let i = 1; i < pts.length; i++) {
      const p = pts[i - 1];
      const c = pts[i];
      const mid = [(p[0] + c[0]) / 2, (p[1] + c[1]) / 2];
      ctx.beginPath();
      ctx.moveTo(last[0], last[1]);
      ctx.quadraticCurveTo(p[0], p[1], mid[0], mid[1]);
      ctx.lineWidth = Math.max(0.5, p[2]);
      ctx.stroke();
      last = mid;
    }
    const end = pts[pts.length - 1];
    ctx.beginPath();
    ctx.moveTo(last[0], last[1]);
    ctx.lineTo(end[0], end[1]);
    ctx.lineWidth = Math.max(0.5, end[2]);
    ctx.stroke();
  }
  ctx.restore();
}

export function drawInk(ctx, page) {
  for (const s of page.strokes || []) drawStroke(ctx, s);
}

/** Distance from point (x, y) to the closest point on a stroke. */
export function distanceToStroke(s, x, y) {
  const pts = s.points;
  if (!pts.length) return Infinity;
  if (pts.length === 1) return Math.hypot(pts[0][0] - x, pts[0][1] - y);
  let best = Infinity;
  for (let i = 1; i < pts.length; i++) {
    const [x0, y0] = pts[i - 1];
    const [x1, y1] = pts[i];
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len2 = dx * dx + dy * dy;
    const t = len2 ? Math.max(0, Math.min(1, ((x - x0) * dx + (y - y0) * dy) / len2)) : 0;
    best = Math.min(best, Math.hypot(x - (x0 + t * dx), y - (y0 + t * dy)));
  }
  return best;
}

/** A page flattened to a canvas, for exports. */
export function flattenPage(page, spec, images, scale = 2, objects = true) {
  // A huge whiteboard would otherwise need a bitmap bigger than the browser allows.
  const k = Math.min(scale, 4096 / Math.max(spec.w, spec.h));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(spec.w * k);
  canvas.height = Math.round(spec.h * k);
  const ctx = canvas.getContext('2d');
  ctx.scale(k, k);
  drawPaper(ctx, page, spec, images, { objects });
  drawInk(ctx, page);
  return canvas;
}
