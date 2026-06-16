---
name: petals-appstore-screenshots
description: >-
  Generate, regenerate, or tweak the Mac App Store marketing screenshots for
  the Petals macOS app — the five branded poster images (2880x1800) used on the
  App Store product page. The workflow builds Petals in a dedicated screenshot
  mode, captures real app windows, and composites them into posters with
  headlines, backgrounds, and decorations. Use this skill whenever the user
  wants to create or update the Petals App Store or store-listing screenshots,
  or to adjust an individual poster's headline, caption, background color, or
  decoration and re-render it — even when they only say "make the screenshots",
  "update the store images", or "redo screenshot 4". Not for the app icon,
  promo videos, ad-hoc or bug-report screenshots, or refactoring the
  screenshot-mode Swift code.
---

# Petals App Store Screenshots

This skill produces the five Mac App Store screenshots for Petals. Each final
poster is a **real app capture** (not a mockup) dropped into a marketing layout
with a headline, gradient background, and optional decorations or panels.

The whole pipeline lives in `AppStore/screenshots/` at the repo root. The app
itself has a built-in **screenshot mode** that makes captures deterministic and
clean. Do not recreate the app UI in HTML — capture the real thing.

## The five screenshots

| # | File | App state captured | Marketing overlay |
|---|------|--------------------|-------------------|
| 1 | `01-year.png` | Year calendar, Minimal theme, demo events | Stickers + "2026 GOALS" text |
| 2 | `02-themes.png` | Year calendar, Tokyo Night dark theme | 9-theme swatch panel |
| 3 | `03-zoom.png` | Quarter zoom view (Jan–Mar) | — |
| 4 | `04-whiteboard.png` | Whiteboard mode, seeded boards | Sticker + text decorations |
| 5 | `05-mac.png` | Year calendar, Classic theme | 3 feature cards panel |

## Workflow

Run these three steps from the repo root. Steps 2–3 are scripts already in
`AppStore/screenshots/`.

### 1. Build the app

```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals \
  -configuration Debug -derivedDataPath /tmp/petals-dd build
```

The capture script expects the app at
`/tmp/petals-dd/Build/Products/Debug/Petals.app`.

### 2. Capture real app windows

```bash
cd AppStore/screenshots && ./capture.sh            # English (en-US) → captures/
cd AppStore/screenshots && SHOT_LANG=ko ./capture.sh   # Korean (ko) → captures/ko/
```

This launches Petals five times in screenshot mode, captures each window, and
writes raw PNGs to `captures/` (English) or `captures/ko/` (Korean). First run
triggers a one-time **Screen Recording permission** prompt for the terminal —
grant it and re-run if any capture comes out empty.

### 3. Composite and render the posters

```bash
cd AppStore/screenshots && ./render.sh             # English: 01-year.png … 05-mac.png
cd AppStore/screenshots && \
  ./render.sh 01-year.ko 02-themes.ko 03-zoom.ko 04-whiteboard.ko 05-mac.ko   # Korean
```

`render.sh` with no args renders the five English `NN-*.html` files; pass scene
basenames to render a specific set (e.g. the Korean `NN-*.ko.html`). Output is
2880x1800 — the App Store deliverables.

### 4. Deliver + upload

Copy the rendered posters into the fastlane locale folders, then upload:

```bash
# from repo root, for f in 01-year 02-themes 03-zoom 04-whiteboard 05-mac:
#   cp AppStore/screenshots/$f.png    fastlane/screenshots/en-US/$f.png
#   cp AppStore/screenshots/$f.ko.png fastlane/screenshots/ko/$f.png
bundle exec fastlane mac upload_listing   # metadata + screenshots, no review submission
```

## Localization (en-US + ko)

The Korean App Store gets its own screenshots — **not** English copies:

- **UI chrome** is captured in Korean via `SHOT_LANG=ko` (`capture.sh` passes
  `-AppleLanguages '(ko)'`). Korean is the app's effective UI language.
- **Demo data** (calendar names, event titles, whiteboard board names) is
  localized in the Swift source, switched by `PETALS_SHOT_LANG` —
  see `EventManager.makeDemoCalendars/makeDemoEvents` and
  `ScreenshotConfig.seedDemoBoards`.
- **Marketing copy** (headline, sub, decorations, panel text) lives in the
  per-locale scene files: `NN-*.html` (English) and `NN-*.ko.html` (Korean).
  Theme names in the swatch panel stay in English (brand names).

When regenerating, always do **both** locales so the listings stay in sync.

## How screenshot mode works (in the app)

Screenshot mode is gated entirely behind the `PETALS_SHOT=1` environment
variable, so normal launches are unaffected. Relevant source:

- `Petals/Petals/Helpers/ScreenshotConfig.swift` — reads env vars:
  `PETALS_SHOT` (activate), `PETALS_SHOT_THEME`, `PETALS_SHOT_ZOOM` (12/3/1),
  `PETALS_SHOT_MODE` (`whiteboard`), `PETALS_SHOT_YEAR`, `PETALS_SHOT_LANG`
  (`ko` for Korean demo data; default `en`).
- `Petals/Petals/Helpers/ScreenshotWindowSizer.swift` — pins the window to a
  fixed **compact** size (`targetWidth = 1600` pt) and disables state
  restoration. See the legibility gotcha below before changing this number.
- `EventManager.loadDemoEvents(...)` — synthetic demo calendars + events, no
  EventKit permission required (events are never saved to the store).
- `ContentView` — applies the initial theme/zoom/mode and loads demo events.
- `PetalsApp` — uses an in-memory SwiftData store (no CloudKit, no user data)
  and seeds demo whiteboard boards.

If this code is ever removed, the captures will show the user's real data and
require live permission prompts — keep it intact.

## Composition layer (`AppStore/screenshots/`)

- `NN-*.html` — one per screenshot. Each defines a `SCENE` object: poster
  background/headline, the `shot` capture path, optional `decorations`, optional
  `panel` (`themes` or `features`).
- `lib/build.js` — reads `SCENE`, builds the poster DOM.
- `lib/styles.css` — poster + panel + decoration styling.
- `lib/winid.swift` — finds the capture target window id.
- `capture.sh`, `render.sh` — the two pipeline scripts.

To tweak a screenshot (headline text, colors, sticker placement), edit the
`SCENE` in the relevant HTML file and re-run `./render.sh` only — no rebuild or
recapture needed unless the app UI itself changed.

## Hard-won gotchas

These cost real debugging time. Respect them.

- **Launch with `open -n --env`, not the binary directly.** Direct execution of
  `Petals.app/Contents/MacOS/Petals` fails to create a window in a scripted
  context. `open` is the reliable GUI launch. `capture.sh` already does this.
- **Stale window-frame prefs hijack captures.** The app's saved window frame can
  be off-screen or tiny (e.g. 99x107), and restoration reapplies it.
  `capture.sh` backs up the `com.idealapp.Petals` defaults domain, clears it for
  clean launches, and restores it on exit — so the user's real settings survive.
- **`winid.swift` queries `.optionAll`** so a mis-restored off-screen window is
  still found, and filters out tiny/menu-bar windows by size.
- **Capture-window size drives poster legibility — don't size it to the screen.**
  The poster shows the captured window at ~1150px, so the window's on-screen
  size sets how much it gets downscaled. Sizing it to the whole display (as it
  originally did) made a large-monitor capture ~2553pt wide → downscaled to
  ~0.45x in the poster → **event text unreadable**. Sizing it too small (≤1320pt)
  cramps the year grid until the day number, weekday, and `+1` overflow badge
  **overlap**. `ScreenshotWindowSizer.targetWidth = 1600` pt is the balance:
  no overlap, text as large as it can be. If you change it, re-check the year
  view's top-left day headers for collisions AND the event-label legibility.
- **Locale via `SHOT_LANG`.** `capture.sh` defaults to `-AppleLanguages '(en)'`
  (English App Store). `SHOT_LANG=ko ./capture.sh` switches to `(ko)` and writes
  to `captures/ko/`, also seeding Korean demo data via `PETALS_SHOT_LANG`.
- **Some emoji don't render in headless Chrome.** The butterfly `🦋` rendered as
  a stray "W"; swap any broken decoration emoji for a common one and re-render.
- **Kill cleanly between captures.** Relaunching while a previous instance is
  still alive gets suppressed; `capture.sh` waits for the process table to clear.

## Verifying the result

After `render.sh`, open each `NN-*.png` and check: 2880x1800 dimensions, real
app UI visible (correct language, demo events populated), **event labels
readable** (see the capture-window-size gotcha), day headers not overlapping in
the year view, decorations not clipped by the window edge, panels legible. With
`targetWidth = 1600` the raw `captures/*.png` are ~3200x2000 (2x). Verify both
the English (`NN-*.png`) and Korean (`NN-*.ko.png`) sets.
