# Inkwell web portal

A static site (no build step) that runs in the browser: sign in, create an account with an invite code, library
with folders, and a note editor with pen, highlighter, eraser, text boxes, sticky notes, checklists, tables, stamps
and pictures. Notes are encrypted in the browser before they are sent to the sync server (see `../backend`).

- `index.html`, `js/app.js` the app: sign-in, recovery key, library, settings
- `js/editor.js` the note editor
- `js/crypto.js` all encryption (Web Crypto)
- `js/store.js`, `js/api.js` syncing with the server
- `js/templates.js`, `js/render.js` page backgrounds and drawing (same as the iPad app)
- `admin.html` for the administrator: invite codes, reset codes, accounts
- `_headers` Content-Security-Policy and other security headers for Cloudflare Pages
- Data format shared with the iPad app: `../docs/SYNC-FORMAT.md`

## Deploying

The **Deploy web portal** workflow publishes this folder to Cloudflare Pages as `inkwell-web`
(address: `https://inkwell-web.pages.dev`). It needs the same GitHub secrets as the backend, and the Cloudflare
API token must also include **Cloudflare Pages: Edit**.

Optional: add a repository **variable** (Settings > Secrets and variables > Actions > Variables) called
`INKWELL_API_URL` with your Worker address so the sign-in page is pre-filled.

The security headers only allow connections to `*.workers.dev`. If you move the Worker to your own domain,
change `connect-src` in `_headers`.

## Using it on an iPad

Open the address in Safari. Apple Pencil draws with pressure. A finger scrolls (turn off "Pen only" to draw with a
finger). Add to Home Screen from the Share menu for a full-screen app.

## Not in the web version

Custom templates made on the iPad are kept but not offered here, shapes were removed from the app, and handwriting
recognition (search inside handwriting, Word export, dictation) is iPad only. Export from the web is PNG per page and
Print / Save as PDF.
