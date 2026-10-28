# Inkwell

iPad Air notes app for Apple Pencil Pro. SwiftUI + PencilKit, iPadOS 17.5+.

- Handwriting with the system PencilKit tool palette (squeeze, barrel roll and haptics come from PencilKit)
- Folders, 8 built-in templates, and "save page as template"
- Insert photos from the library or take one with the camera, then move and resize
- Export: PDF, Word (.docx), PNG, plain text, RTF, Inkwell backup. Print too.
- Text, Word and RTF exports use on-device handwriting recognition (Apple Vision)

UI design: see the "Inkwell iPad Notes" canvas made with Claude Design.

## Status

Written without access to a Mac, so it has **not been compiled yet**. Expect the first
CI run to surface a few compile errors; paste the log back and they get fixed quickly.
Not in v1: text boxes, searching inside handwriting (search is by title only).

## Build to TestFlight from GitHub (no Mac needed)

1. **Apple Developer Program** membership (https://developer.apple.com/programs/).
2. **Register the bundle ID** `au.org.hornsbyanglican.inkwell` (Certificates, Identifiers & Profiles > Identifiers),
   or change it in `project.yml` first.
3. **Create the app** in App Store Connect (My Apps > + > New App, iOS, that bundle ID).
4. **Create an API key**: App Store Connect > Users and Access > Integrations > App Store Connect API >
   generate a key with the **Admin** role. Download the `.p8` (only once). Note the Key ID and Issuer ID.
5. **Create a GitHub repo** with this folder as its root and add these Actions secrets
   (Settings > Secrets and variables > Actions):

   | Secret | Value |
   |---|---|
   | `APPLE_TEAM_ID` | 10-character team ID (developer.apple.com > Membership) |
   | `APPSTORE_KEY_ID` | Key ID from step 4 |
   | `APPSTORE_ISSUER_ID` | Issuer ID from step 4 |
   | `APPSTORE_KEY_P8` | Full contents of the `.p8` file, including the BEGIN/END lines |

6. Push to `main` (or run the workflow from the Actions tab). The Mac runner generates the Xcode
   project, signs with cloud-managed certificates, and uploads. Each run bumps the build number.
7. In App Store Connect > TestFlight, wait for processing (~10-30 min), add testers, install via the TestFlight app.

## Local build on a Mac

```bash
brew install xcodegen
swift Tools/make_icon.swift Assets.xcassets/AppIcon.appiconset/icon.png
xcodegen generate
open Inkwell.xcodeproj
```
