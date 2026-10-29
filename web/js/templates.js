// Page backgrounds. Mirrors Templates.swift in the iPad app so a note looks the same on both.

export const PAGE_W = 794;
export const PAGE_H = 1123;

export const TEMPLATES = [
  { id: 'blank', title: 'Blank', category: 'Basic' },
  { id: 'ruled', title: 'Ruled', category: 'Basic' },
  { id: 'grid', title: 'Grid', category: 'Basic' },
  { id: 'dots', title: 'Dot grid', category: 'Basic' },
  { id: 'onePoint', title: 'One-point perspective', category: 'Art guides' },
  { id: 'twoPoint', title: 'Two-point perspective', category: 'Art guides' },
  { id: 'face', title: 'Face proportions', category: 'Art guides' },
  { id: 'figure', title: 'Figure (8 heads)', category: 'Art guides' },
  { id: 'colourWheel', title: 'Colour wheel', category: 'Art guides' },
  { id: 'valueScale', title: 'Value scale', category: 'Art guides' },
  { id: 'thirds', title: 'Composition guides', category: 'Art guides' },
  { id: 'isometric', title: 'Isometric grid', category: 'Art guides' },
  { id: 'meeting', title: 'Meeting minutes', category: 'Planning' },
  { id: 'planner', title: 'Weekly planner', category: 'Planning' },
  { id: 'cornell', title: 'Cornell notes', category: 'Study' },
  { id: 'sermon', title: 'Sermon outline', category: 'Church' },
];

export const CATEGORIES = ['Basic', 'Art guides', 'Planning', 'Study', 'Church'];

// Paper sizes in points at 96 dpi, portrait. The same list as the iPad app.
export const PAPER_PRESETS = [
  { id: 'a4', title: 'A4', detail: '210 × 297 mm', w: 794, h: 1123 },
  { id: 'a5', title: 'A5', detail: '148 × 210 mm', w: 559, h: 794 },
  { id: 'a6', title: 'A6', detail: '105 × 148 mm', w: 397, h: 559 },
  { id: 'b5', title: 'B5', detail: '176 × 250 mm', w: 665, h: 945 },
  { id: 'letter', title: 'US Letter', detail: '8.5 × 11 in', w: 816, h: 1056 },
  { id: 'legal', title: 'US Legal', detail: '8.5 × 14 in', w: 816, h: 1344 },
];

export const WHITEBOARD_SIZES = [
  { id: 'small', title: 'Small', w: 2000, h: 1500 },
  { id: 'medium', title: 'Medium', w: 3000, h: 2000 },
  { id: 'large', title: 'Large', w: 4000, h: 3000 },
  { id: 'huge', title: 'Huge', w: 6000, h: 4000 },
];

export const PAPER_COLOURS = [
  ['White', '#FFFFFF'], ['Cream', '#FBF6E9'], ['Light blue', '#EEF4FF'], ['Light grey', '#F2F2F2'], ['Soft yellow', '#FFF9D6'],
];
export const COVER_COLOURS = [
  ['Blue', '#2F5BEA'], ['Clay', '#D97757'], ['Green', '#4FB286'], ['Purple', '#8E44AD'], ['Red', '#C0392B'], ['Charcoal', '#1B2430'],
];
export const WHITEBOARD_BACKGROUNDS = ['blank', 'grid', 'dots'];
export const templateTitle = (id) => TEMPLATES.find((t) => t.id === id)?.title ?? id;

const RULE = '#ccd9f0';
const STRONG = '#8c99b3';
const GUIDE = '#9eb8ed';
const CLAY = '#edb89e';
const LABEL = '#5c6673';

function line(ctx, x0, y0, x1, y1, color, width = 1) {
  ctx.beginPath();
  ctx.moveTo(x0, y0);
  ctx.lineTo(x1, y1);
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
}

function dot(ctx, x, y, r, color) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
}

function ring(ctx, x, y, r, color, width) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
}

function label(ctx, text, x, y) {
  ctx.save();
  ctx.font = '600 11px -apple-system, Helvetica, Arial, sans-serif';
  ctx.fillStyle = LABEL;
  ctx.textBaseline = 'top';
  ctx.fillText(text.toUpperCase(), x, y);
  ctx.restore();
}

function box(ctx, x, y, w, h, color) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, 6);
  ctx.strokeStyle = color;
  ctx.lineWidth = 1.2;
  ctx.stroke();
}

function rectStroke(ctx, x, y, w, h, color, width) {
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.strokeRect(x, y, w, h);
}

function ovalStroke(ctx, cx, cy, rx, ry, color, width) {
  ctx.beginPath();
  ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
}

const range = (from, to, step) => {
  const out = [];
  for (let v = from; v < to; v += step) out.push(v);
  return out;
};

export function drawTemplate(ctx, kind, w = PAGE_W, h = PAGE_H) {
  ctx.save();
  switch (kind) {
    case 'blank':
      break;

    case 'ruled':
      for (const y of range(96, h - 40, 32)) line(ctx, 36, y, w - 36, y, RULE);
      line(ctx, 84, 0, 84, h, '#f0b8b8');
      break;

    case 'grid':
      for (let x = 0; x <= w; x += 28) line(ctx, x, 0, x, h, RULE, 0.8);
      for (let y = 0; y <= h; y += 28) line(ctx, 0, y, w, y, RULE, 0.8);
      break;

    case 'dots':
      for (let x = 28; x < w; x += 28) for (let y = 28; y < h; y += 28) dot(ctx, x, y, 1.2, STRONG);
      break;

    case 'cornell': {
      label(ctx, 'Topic', 36, 30);
      line(ctx, 36, 72, w - 36, 72, STRONG, 1.5);
      const bottom = h - 230;
      line(ctx, 230, 72, 230, bottom, STRONG, 1.5);
      label(ctx, 'Cues', 36, 84);
      label(ctx, 'Notes', 246, 84);
      for (const y of range(128, bottom, 32)) line(ctx, 246, y, w - 36, y, RULE);
      line(ctx, 36, bottom, w - 36, bottom, STRONG, 1.5);
      label(ctx, 'Summary', 36, bottom + 12);
      for (const y of range(bottom + 64, h - 36, 32)) line(ctx, 36, y, w - 36, y, RULE);
      break;
    }

    case 'meeting':
      label(ctx, 'Meeting', 36, 30);
      line(ctx, 120, 52, w - 260, 52, STRONG);
      label(ctx, 'Date', w - 240, 30);
      line(ctx, w - 200, 52, w - 36, 52, STRONG);
      label(ctx, 'Attendees', 36, 84);
      for (const y of [130, 162]) line(ctx, 36, y, w - 36, y, RULE);
      label(ctx, 'Agenda', 36, 190);
      for (const y of range(238, 430, 32)) line(ctx, 36, y, w - 36, y, RULE);
      label(ctx, 'Notes', 36, 450);
      for (const y of range(498, 790, 32)) line(ctx, 36, y, w - 36, y, RULE);
      label(ctx, 'Actions', 36, 810);
      for (const y of range(858, h - 40, 32)) {
        line(ctx, 64, y, w - 36, y, RULE);
        rectStroke(ctx, 36, y - 18, 16, 16, STRONG, 1);
      }
      break;

    case 'planner': {
      label(ctx, 'Week of', 36, 30);
      line(ctx, 110, 52, w - 36, 52, STRONG);
      ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'].forEach((d, i) => {
        const y = 76 + i * 150;
        box(ctx, 36, y, w - 72, 140, STRONG);
        label(ctx, d, 46, y + 8);
      });
      const half = (w - 72 - 14) / 2;
      ['Saturday', 'Sunday'].forEach((d, i) => {
        const x = 36 + i * (half + 14);
        const y = 76 + 5 * 150;
        box(ctx, x, y, half, h - y - 36, STRONG);
        label(ctx, d, x + 10, y + 8);
      });
      break;
    }

    case 'sermon': {
      const sections = [['Text and theme', 2], ['Big idea', 2], ['Point 1', 4], ['Point 2', 4], ['Point 3', 4], ['Application', 3], ['Prayer', 2]];
      let y = 36;
      for (const [name, lines] of sections) {
        label(ctx, name, 36, y);
        y += 40;
        for (let i = 0; i < lines; i++) {
          y += 32;
          line(ctx, 36, y, w - 36, y, RULE);
        }
        y += 14;
      }
      break;
    }

    case 'onePoint': {
      const horizon = 480;
      const vx = w / 2;
      for (let x = 0; x <= w; x += 66) {
        line(ctx, vx, horizon, x, 0, GUIDE, 0.8);
        line(ctx, vx, horizon, x, h, GUIDE, 0.8);
      }
      for (let y = 0; y <= h; y += 66) {
        line(ctx, vx, horizon, 0, y, GUIDE, 0.8);
        line(ctx, vx, horizon, w, y, GUIDE, 0.8);
      }
      line(ctx, 0, horizon, w, horizon, STRONG, 1.6);
      dot(ctx, vx, horizon, 5, STRONG);
      label(ctx, 'Horizon line', 36, horizon - 22);
      label(ctx, 'Vanishing point', vx + 12, horizon + 10);
      break;
    }

    case 'twoPoint': {
      const horizon = 520;
      const v1 = [40, horizon];
      const v2 = [w - 40, horizon];
      for (const x of range(99, w, 99)) line(ctx, x, 0, x, h, RULE, 0.6);
      for (let y = 0; y <= h; y += 70) {
        line(ctx, v1[0], v1[1], w, y, GUIDE, 0.8);
        line(ctx, v2[0], v2[1], 0, y, CLAY, 0.8);
      }
      line(ctx, 0, horizon, w, horizon, STRONG, 1.6);
      dot(ctx, v1[0], v1[1], 5, STRONG);
      dot(ctx, v2[0], v2[1], 5, STRONG);
      label(ctx, 'VP 1', v1[0] + 8, horizon + 10);
      label(ctx, 'VP 2', v2[0] - 46, horizon + 10);
      label(ctx, 'Horizon line', w / 2 - 40, horizon - 22);
      break;
    }

    case 'face': {
      const cx = w / 2, top = 190, fh = 560, fw = 400;
      ovalStroke(ctx, cx, top + fh / 2, fw / 2, fh / 2, STRONG, 1.5);
      line(ctx, cx, top - 30, cx, top + fh + 30, STRONG, 1);
      const marks = [['Top of head', 0], ['Hairline', 0.14], ['Brow', 0.38], ['Eye line', 0.5], ['Nose base', 0.74], ['Mouth', 0.85], ['Chin', 1]];
      for (const [name, f] of marks) {
        const y = top + fh * f;
        line(ctx, cx - fw / 2 - 30, y, cx + fw / 2 + 30, y, GUIDE, 0.9);
        label(ctx, name, 36, y - 14);
      }
      for (let i = 1; i < 5; i++) {
        const x = cx - fw / 2 + (fw * i) / 5;
        line(ctx, x, top + fh * 0.5 - 22, x, top + fh * 0.5 + 22, STRONG, 1);
      }
      label(ctx, 'Eyes sit halfway down. Five eye-widths across.', 36, 60);
      break;
    }

    case 'figure': {
      const top = 70, unit = 120, cx = w / 2;
      line(ctx, cx, top - 10, cx, top + unit * 8 + 10, STRONG, 1);
      const names = ['Chin', 'Nipples', 'Navel', 'Crotch', 'Mid thigh', 'Knee', 'Calf', 'Feet'];
      for (let i = 0; i <= 8; i++) {
        const y = top + unit * i;
        const edge = i === 0 || i === 8;
        line(ctx, cx - 180, y, cx + 180, y, edge ? STRONG : GUIDE, edge ? 1.4 : 0.9);
        if (i < 8) label(ctx, String(i + 1), cx + 192, y + 4);
        if (i > 0) label(ctx, names[i - 1], 36, y - 14);
      }
      ovalStroke(ctx, cx, top + unit / 2, 45, (unit - 16) / 2, GUIDE, 1);
      break;
    }

    case 'colourWheel': {
      const cx = w / 2, cy = 400, r = 300, inner = 90;
      for (let i = 0; i < 12; i++) {
        const a0 = (i / 12) * 2 * Math.PI - Math.PI / 2 - Math.PI / 12;
        const a1 = a0 + (2 * Math.PI) / 12;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.arc(cx, cy, r, a0, a1);
        ctx.closePath();
        ctx.fillStyle = `hsla(${(i / 12) * 360}, 75%, 62%, 0.55)`;
        ctx.fill();
        ctx.strokeStyle = STRONG;
        ctx.lineWidth = 0.8;
        ctx.stroke();
      }
      ctx.beginPath();
      ctx.arc(cx, cy, inner, 0, Math.PI * 2);
      ctx.fillStyle = '#fff';
      ctx.fill();
      ctx.strokeStyle = STRONG;
      ctx.lineWidth = 1;
      ctx.stroke();
      label(ctx, 'Colour wheel', 36, 36);
      for (const y of range(780, h - 40, 32)) line(ctx, 36, y, w - 36, y, RULE);
      break;
    }

    case 'valueScale': {
      const n = 9;
      const bw = (w - 72) / n;
      label(ctx, 'Value scale: row 1 is the guide, fill the rest yourself', 36, 36);
      for (let row = 0; row < 5; row++) {
        const y = 70 + row * 130;
        for (let i = 0; i < n; i++) {
          const x = 36 + bw * i;
          if (row === 0) {
            const v = Math.round(255 * (1 - i / (n - 1)));
            ctx.fillStyle = `rgb(${v},${v},${v})`;
            ctx.fillRect(x, y, bw, 100);
          }
          rectStroke(ctx, x, y, bw, 100, STRONG, 0.8);
          label(ctx, String(i + 1), x + 4, y + 104);
        }
      }
      for (const y of range(780, h - 40, 32)) line(ctx, 36, y, w - 36, y, RULE);
      break;
    }

    case 'thirds': {
      const inset = 36;
      const rx = inset, ry = inset, rw = w - 2 * inset, rh = h - 2 * inset;
      rectStroke(ctx, rx, ry, rw, rh, STRONG, 1.5);
      for (let i = 1; i <= 2; i++) {
        const f = i / 3;
        line(ctx, rx + rw * f, ry, rx + rw * f, ry + rh, STRONG, 1);
        line(ctx, rx, ry + rh * f, rx + rw, ry + rh * f, STRONG, 1);
      }
      line(ctx, rx, ry, rx + rw, ry + rh, GUIDE, 0.8);
      line(ctx, rx + rw, ry, rx, ry + rh, GUIDE, 0.8);
      for (let i = 1; i <= 2; i++) for (let j = 1; j <= 2; j++) ring(ctx, rx + (rw * i) / 3, ry + (rh * j) / 3, 14, CLAY, 1.5);
      label(ctx, 'Rule of thirds, power points and diagonals', inset + 6, 12);
      break;
    }

    case 'isometric': {
      const step = 46;
      const slope = 0.57735;
      for (let x = 0; x <= w; x += step * 0.8660254) line(ctx, x, 0, x, h, RULE, 0.7);
      const lower = -Math.floor((w * slope) / step) - 1;
      const upper = Math.floor(h / step) + 1;
      for (let k = lower; k <= upper; k++) {
        const y0 = k * step;
        line(ctx, 0, y0, w, y0 + w * slope, RULE, 0.7);
        line(ctx, 0, y0 + w * slope, w, y0, RULE, 0.7);
      }
      break;
    }

    default:
      break;
  }
  ctx.restore();
}

/** Draws a template onto a page of any size. The layouts are designed for A4's width (794) and are scaled
 *  to the page's width, so A5, A6 and B5, which have the same proportions, look exactly like A4. */
export function drawTemplateFitted(ctx, kind, w, h) {
  const scale = w / PAGE_W;
  ctx.save();
  ctx.scale(scale, scale);
  drawTemplate(ctx, kind, PAGE_W, h / scale);
  ctx.restore();
}

/** A whiteboard background: plain, a grid or dots spread over the whole board at a fixed spacing. */
export function drawBoard(ctx, kind, w, h) {
  ctx.save();
  if (kind === 'grid') {
    for (let x = 0; x <= w; x += 28) line(ctx, x, 0, x, h, RULE, 0.8);
    for (let y = 0; y <= h; y += 28) line(ctx, 0, y, w, y, RULE, 0.8);
  } else if (kind === 'dots') {
    ctx.fillStyle = STRONG;
    ctx.beginPath();
    for (let x = 14; x < w; x += 28) {
      for (let y = 14; y < h; y += 28) {
        ctx.moveTo(x + 1.2, y);
        ctx.arc(x, y, 1.2, 0, Math.PI * 2);
      }
    }
    ctx.fill();
  }
  ctx.restore();
}
