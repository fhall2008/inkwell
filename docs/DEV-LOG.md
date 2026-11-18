# Inkwell dev log

A short diary of what we change and why, written so Fin can follow along. Newest entry first.
(The rule for keeping it is in `CLAUDE.md`.)

## Open issues (found, not yet fixed)

1. **Every note loads at launch** (`Store.load()`), drawings included, on the main thread. Slow start and high memory once there are many notes. Fix: load a light index, open notes on demand.
2. **Whole-page re-encode on every stroke.** `canvasViewDrawingDidChange` rebuilds the drawing data each time. Pages with lots of ink may lag. Fix: debounce it.
3. **Silent failures.** Disk and Keychain writes use `try?`, so errors vanish. A full iPad could lose a note with no message. Fix: surface errors.
4. **Backup import trusts file names.** A crafted backup could write outside the images folder. Low risk for a family app. Fix: reject names containing `/` or `..`.
5. **Stray `# test` comment** on the Swift version line in `project.yml`.

---

## 2026-11-18: Fix: remote edits no longer overwritten by an open note
**What:** When another device changes a note that is open on the iPad, the editor now picks up the new version. If you had just made an edit yourself (under a second ago), yours is kept, the same rule the sync engine uses.
**Why:** The editor works on its own copy of the note. The sync could update the stored note, but the editor never noticed, so closing or saving wrote the stale copy back over the newer one.
**How:** `Store` now announces "note X changed remotely" (a Combine `PassthroughSubject`). The editor listens, swaps in the new note, and changes a `reloadToken` so SwiftUI rebuilds the pages. The rebuild is needed because the drawing canvas only reads its data once, when created.
**Lesson:** Two copies of the same data will drift apart. Either keep one source of truth, or make every copy listen for changes. Also: tell listeners *that* something changed with an event, not by comparing timestamps. Timestamp checks falsely fire on your own saves.
**Not tested:** no Mac here, so unbuilt. To try it: open a note on the iPad, edit the same note on the web portal, wait up to 60 s. The iPad page should refresh by itself.
**Files:** `Sources/Store.swift`, `Sources/NoteEditorView.swift`.

## 2026-11-18: Read-through review of the code
**What:** Read about a third of the code (canvas, compat shims, Keychain, dictation, renderer, crypto, sync engine, store, editor saves). No code changed.
**Looks sound:**
- *iOS 16 support:* iOS 17-only SwiftUI pieces are replaced by stand-ins in `Compat.swift`. Permission texts for mic, camera and speech are present, so those features won't crash on first use.
- *Encryption:* password is stretched with PBKDF2, a random master key is wrapped by the password and by a recovery key, notes are sealed with AES-GCM. Keychain items are "this device only". (Not yet compared byte-for-byte with the web's `crypto.js`.)
- *Sync:* handles conflicts, retries interrupted uploads, skips unreadable notes instead of stopping, and survives an interrupted password change.
**Problems found:** see Open issues above.
**Lesson:** A review that lists *what is good* as well as what is wrong tells you what not to break later. Also, "it compiles" and "it's correct" are different things. The compiler caught the iOS 17 API problems, but it can't catch issue 1 (two copies of the same data drifting apart).
**Files:** none changed.

## 2026-11-18: Removed duplicate "Copy" files, refreshed the README
**What:** Deleted `Sources - Copy`, `Tools - Copy`, `Assets.xcassets - Copy`, `.github - Copy`, `project - Copy.yml`, `README - Copy.md`. README now says iOS 16+, tested on 16.7, and no longer says "not compiled". Fixed the wrong bundle ID in the setup steps.
**Why:** The copies were old snapshots (missing about 15 source files) and cluttered the repo. Git already keeps history, so nothing is lost.
**Lesson:** Don't make "- Copy" backups inside a project. Commits are the backup, and you can always get an old version back with `git`. Stale docs are a bug too: the README disagreed with `project.yml` on both iOS version and bundle ID.
**Files:** `README.md`, the deleted folders and files.

## 2026-11-18: Moved to the `david` branch
**What:** Created branch `david` and made the changes there.
**Why:** Keeps `main` (which feeds the TestFlight build) untouched until we're happy with the work.
**Lesson:** A branch is a safe place to experiment. Merge only when it works.
