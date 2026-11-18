# Working on Inkwell

Inkwell is an iPad handwriting notes app (SwiftUI + PencilKit) with a Cloudflare sync backend (`backend/`) and a web portal (`web/`). See `README.md`.

## This project is also a teaching project

David is a very experienced programmer. His grandson Fin is 18 and learning. Claude does most of the coding, but the point is that **Fin learns to be a better programmer by following what we do and why**.

### Rule: log every change in `docs/DEV-LOG.md`

For every change (code, config, docs, deletions), add an entry **in the same commit** as the change. Newest entry at the top.

Entry format (keep it short; Fin has a limited attention span):

```
## YYYY-MM-DD: Short title
**What:** one or two lines on what changed.
**Why:** the reason, in plain words.
**Lesson:** one transferable programming idea Fin can reuse (skip if there isn't a real one).
**Files:** the main files touched.
```

Guidelines:
- Aim for under about 10 lines per entry. Plain words. Explain any jargon the first time.
- Say *why* not just *what*. Mention alternatives we rejected if that teaches something.
- Record reviews, analysis and decisions too, not only edits. If something is found but not fixed, put it in the "Open issues" list at the top of the log.
- When an open issue is fixed, move it out of that list and log the fix.
- Be honest: if something was not tested or is a guess, say so.

## Other conventions
- Work on the `david` branch, not `main`, unless told otherwise.
- The app is built by GitHub Actions (no Mac available). Nothing can be compiled locally, so be careful and say so when a change is untested.
- Minimum iOS is 16. Use the stand-ins in `Sources/Compat.swift` instead of iOS 17-only APIs.
