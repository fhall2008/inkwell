# Inkwell dev log

A short diary of what we change and why, written so Fin can follow along. Newest entry first.
(The rule for keeping it is in `CLAUDE.md`.)

## Open issues (found, not yet fixed)

1. **Remote edits can be overwritten.** An open note keeps its own copy. Edit it on the web while it's open on the iPad and the iPad's next save wins. Fix: refresh the editor when a remote change arrives.
2. **Every note loads at launch** (`Store.load()`), drawings included, on the main thread. Slow start and high memory once there are many notes. Fix: load a light index, open notes on demand.
3. **Whole-page re-encode on every stroke.** `canvasViewDrawingDidChange` rebuilds the drawing data each time. Pages with lots of ink may lag. Fix: debounce it.
4. **Silent failures.** Disk and Keychain writes use `try?`, so errors vanish. A full iPad could lose a note with no message. Fix: surface errors.
5. **Backup import trusts file names.** A crafted backup could write outside the images folder. Low risk for a family app. Fix: reject names containing `/` or `..`.
6. **Stray `# test` comment** on the Swift version line in `project.yml`.

---

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
