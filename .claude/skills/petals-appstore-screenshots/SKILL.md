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
cd AppStore/screenshots && ./capture.sh
```

This launches Petals five times in screenshot mode, captures each window, and
writes raw PNGs to `captures/`. First run triggers a one-time **Screen
Recording permission** prompt for the terminal — grant it and re-run if any
capture comes out empty.

### 3. Composite and render the posters

```bash
cd AppStore/screenshots && ./render.sh
```

This renders the five `NN-*.html` files with headless Chrome at 2x, producing
the final `01-year.png` … `05-mac.png` at 2880x1800 — the App Store deliverables.

## How screenshot mode works (in the app)

Screenshot mode is gated entirely behind the `PETALS_SHOT=1` environment
variable, so normal launches are unaffected. Relevant source:

- `Petals/Petals/Helpers/ScreenshotConfig.swift` — reads env vars:
  `PETALS_SHOT` (activate), `PETALS_SHOT_THEME`, `PETALS_SHOT_ZOOM` (12/3/1),
  `PETALS_SHOT_MODE` (`whiteboard`), `PETALS_SHOT_YEAR`.
- `Petals/Petals/Helpers/ScreenshotWindowSizer.swift` — pins the window to a
  fixed size and disables state restoration.
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
- **Force English UI.** `capture.sh` passes `-AppleLanguages '(en)'` so the
  toolbar and month labels render in English for the (English) App Store.
- **Some emoji don't render in headless Chrome.** The butterfly `🦋` rendered as
  a stray "W"; swap any broken decoration emoji for a common one and re-render.
- **Kill cleanly between captures.** Relaunching while a previous instance is
  still alive gets suppressed; `capture.sh` waits for the process table to clear.

## Verifying the result

After `render.sh`, open each `NN-*.png` and check: 2880x1800 dimensions, real
app UI visible (English, demo events populated), decorations not clipped by the
window edge, panels legible. The raw `captures/*.png` should be 2560x1600.
