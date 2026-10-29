# Inkwell sync data format

What the iPad app and the web portal exchange through the sync server. Everything below is JSON that is
encrypted on the device before upload, so the server never sees it. The web portal (`web/js/`) is the
reference implementation; the iPad app must read and write the same shapes.

## Encryption (see `web/js/crypto.js`)

- `password --PBKDF2-SHA256, 600000 rounds, salt from the server--> 64 bytes`.
  First 32 bytes = `encKey` (never sent). Last 32 bytes, base64 = `loginKey` (sent to `/auth/login`).
- Every blob is `nonce (12 bytes) || AES-256-GCM(masterKey, nonce, plaintext, aad)` where
  `aad = "<kind>:<id>"` (for example `note:3F2A...`). Swapping blobs between ids fails to decrypt.
- Object `envelope` (kind `envelope`, plaintext JSON, not further encrypted):
  `{ "v": 1, "pw": base64(seal(encKey, master, "inkwell-envelope-v1:pw")), "rec": base64(seal(recoveryKey, master, "inkwell-envelope-v1:rec")) }`.
  During a password change an extra `"pw2"` (same wrap, new key) may be present; try `pw` then `pw2`.
- Recovery key: 32 random bytes shown as 52 characters of `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` in groups of 4.

## Objects

| id | kind | plaintext |
|---|---|---|
| note UUID (uppercase) | `note` | the note document below |
| `folders` | `folders` | `{ "v": 1, "folders": [{ "id": "...", "name": "..." }] }` |
| `templates` | `template` | `{ "v": 1, "templates": [...] }` (iPad custom templates; the web leaves it alone) |
| `stamps` | `stamps` | `{ "v": 1, "stamps": [ { "id", "name", "text", "colorHex", "fontSize", "bold", "border", "rotation", "opacity" } ] }` the person's saved custom stamps. Every field must be present. |
| `img-<random>` | `image` | raw JPEG or PNG bytes |
| `envelope` | `envelope` | see above |

## Note document

```json
{
  "v": 1,
  "id": "UUID",
  "title": "Sunday sermon outline",
  "folderId": "folder id or null",
  "template": "ruled",
  "modified": 1761700000000,
  "pages": [
    {
      "id": "UUID",
      "background": "img-... or omitted (an imported PDF page; replaces the template)",
      "strokes": [ { "ink": "pen", "color": "#1B2430", "points": [[x, y, width], ...] } ],
      "images":  [ { "id": "UUID", "file": "img-...", "mime": "image/jpeg", "x": 0, "y": 0, "width": 320, "height": 240 } ],
      "objects": [ { "id": "UUID", "kind": "text", "x": 80, "y": 160, "width": 400, "height": 40,
                     "colorHex": "#1B2430", "fillHex": null, "lineWidth": 3, "text": "", "fontSize": 18,
                     "design": "sans", "bold": false, "italic": false, "list": "none",
                     "items": [], "cells": [] } ]
    }
  ]
}
```

- Page space is in points at 96 dpi, origin top-left, the same as the iPad app. A4 portrait is 794 x 1123.
- Notebooks and whiteboards add these optional fields to the note (a note without them is an A4 portrait note on white paper):
  `kind` (`"note"`, `"notebook"` or `"whiteboard"`), `pageWidth`, `pageHeight` (points; every page of a note is the same size),
  `cover` (notebook cover colour, `"#RRGGBB"`), `paper` (paper colour), `pageNumbers` (true or false).
  Sizes used: A4 794x1123, A5 559x794, A6 397x559, B5 665x945, US Letter 816x1056, US Legal 816x1344 (swap for landscape);
  whiteboards 2000x1500, 3000x2000, 4000x3000 or 6000x4000. A whiteboard has exactly one page and its `template` is
  `blank`, `grid` or `dots`, drawn at a fixed 28-point spacing over the whole board.
- Templates are designed for a 794-wide page and are scaled to the page's width, so A5, A6 and B5 look the same as A4.
- `template` values: `blank ruled grid dots cornell meeting planner sermon onePoint twoPoint face figure colourWheel valueScale thirds isometric`.
- Object `kind` values: `text sticky checklist table stamp` and the shapes `line arrow rectangle ellipse triangle star`.
  Unknown kinds are skipped, not deleted. Object fields match the iPad `PageObject` struct. `items` is
  `[{id, text, done}]`; `cells` is a grid of strings.
- Every object may also carry `rotation` (degrees, tilt around the object's centre), `opacity` (0.1 to 1) and, for stamps,
  `border` (`none box rounded oval double`; missing means `rounded`). Missing `rotation` is 0 and missing `opacity` is 1.
  Stamp `text` may have several lines. Shapes use `lineWidth`, `colorHex` and optional `fillHex` (not for `line` and `arrow`),
  and are drawn inside the object's `width` x `height` box: line and arrow run along the middle of the box, a star is
  inscribed in the smaller side, and an arrow has a 16 x 10 point head.
- A note may have a `watermark`: `{ text, colorHex, opacity, angle, size, border, tiled }` (all present). It is drawn on every page
  above the paper and template but behind pictures, objects and ink. Text is upper-cased; `border` uses the stamp border names;
  `tiled` repeats it in staggered rows. A whiteboard has none.
- Stroke `ink`: `pen`, `pencil`, `marker`/`highlighter` (semi-transparent). The iPad should map other PencilKit inks to
  the nearest of these when exporting and keep the original ink name in an extra `inkType` field so it can restore it.
- Stroke points are `[x, y, width]` where width is the line width in page points at that point.
  iPad to web: use `PKStrokePoint.location` and `size.width` (apply the stroke's transform).
  Web to iPad: build `PKStrokePoint(location:, timeOffset:, size: CGSize(width:, height:), opacity: 1, force: 1, azimuth: 0, altitude: .pi/2)`.
- Whoever saves last wins per object. The server keeps the last 10 versions of each object.
