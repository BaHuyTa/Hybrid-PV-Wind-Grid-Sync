# Road Show deck — what changed

**1 September 2026** · changes to `docs/RoadShow Deck - share.html`, plus three new files in `docs/`.

Nothing is committed yet — this is a summary of work sitting in the working tree.

---

## Why this was fiddly

The deck is a single bundled HTML file. All of its assets — fonts, React, Babel, and the slide
source itself — are gzipped, base64-encoded, and stored in a `__bundler/manifest` block inside
the file. You cannot edit a slide by opening the HTML and searching for the text.

Every change below was made by unpacking that manifest, editing the JSX inside it, and
repacking. Two resources were touched:

| Resource | What it is |
|---|---|
| `bd3303cc-…` | `roadshow-scenes.jsx` — all eleven slides |
| `c6e35238-…` | `roadshow-deck.jsx` — the presenter driver (beats, key handling) |

---

## One real bug

**Slide 09, the live-demo cue card, went permanently black after about 9 seconds.**

It is the deck's one looping slide, and its clock ran unbounded — past the section's own
fade-out. The screen went black and stayed black until you navigated away. That is exactly the
slide you dwell on longest, because it is the one you stand in front of while showing the
Simulink model.

Fixed in the deck driver: the loop clock is now held inside the section window. The breathing
pulse runs off wall time, so it keeps animating. Verified with a 30-second dwell.

---

## Layout and typography fixes

### Slide 02 · Why this matters
The bold kicker line sat 4 px below the retiring coal/gas boxes. Moved from y=768 to y=800 for a
36 px gap.

### Slide 03 · What we are building
"400 V / 50 Hz" is long enough to trip the number auto-shrink to 46 px. Because the caption
flows underneath the number, "grid connection" ended up ~22 px higher than "solar array",
"wind turbine" and "shared DC bus". The numbers now sit in a fixed-height row with a 68 px
baseline reference, so all five numbers share a baseline and all five captions start on the
same line.

### Slide 04 · The system — four fixes
1. **"ANTI-ISLANDING" overflowed its box.** The title measures 190.5 px in Archivo 800 at 21 px;
   with an 18 px inset that needs 208.5 px inside a 200 px card. The card is now wider and
   nudged left (x 1200→1185, width 200→222) with both connectors moved to match (1194→1179 in,
   1400→1407 out). The title stays at the full 21 px, with the same internal padding as
   "BOOST + MPPT".
   *An earlier attempt shrank the type to 18 px instead — that fit, but it read as misaligned
   against the other card titles, so it was reverted.*
2. **"PCC" was crowding**, actually touching the relay box's right border. Now 15 px with
   tighter letterspacing, and moved with its junction dot to x=1437, centred in the corridor
   between the box and the grid circle.
3. **"SHARED DC BUS" was orphaned** — drawn above where the bus line starts, so it read as a
   floating header in empty grey rather than a label for the line. Moved down (icon y 16→132,
   title 82→198, sub 104→220) to sit alongside the line's upper run.
4. "trip < 2 s" → "Trip < 2 s".

### Slide 05 · The three jobs
"PANEL VOLTAGE" had a line through it. It was not the axis — it was the power curve's own tail,
which flattens to y≈127 exactly where the label sat at y=132. Moved below the axis (y=156),
which is where an x-axis label belongs anyway.

### Slide 06 · What "done" looks like
Straight quotes in the section label replaced with typographic quotes, matching the rest of the
deck.

### Slide 07 · Where we are
The descenders in "plant models", "control design" and "validation / test infra" were clipped
2.4 px by the SVG's bottom edge. Gantt viewBox extended by 6 px.

### Slide 10 · Our differentiator
The microphone-feedback trace started and ended mid-air (its envelope had a 0.35 floor, so it
never reached zero), ran across the speaker glyph, and nearly touched the SCR chip. It now
tapers to nothing at both ends, spans mic-edge to speaker-edge with ~10 px clearance either
side, peak amplitude trimmed 74→68 for 18 px under the chip, and the squeal frequency eased
from 8 to 6.4 cycles so the crammed section reads instead of smearing.

### Deck-wide
Small grey captions sentence-cased: *Measure the grid, Inject power, Solar array, Wind turbine,
Shared DC bus, Grid connection, Simulation – MATLAB…, Spinning mass*, and the slide-07 legend.

Left alone deliberately: the letterspaced ALL-CAPS micro-labels (they are the deck's design
language), `dq-frame PI control` (capitalising breaks the notation), and the Gantt bar labels
and status lists (content, not captions).

---

## How it was checked

Every slide was driven through every build step — 11 slides, 50 steps — with each text element
measured against its container and the slide bounds in screen space. The only findings left are
three Gantt bar labels that overhang their bars *during* slide 07's draw animation; they settle
correctly, confirmed visually.

To re-render the whole deck yourself as images:

```bash
# 11 pages, one per slide, every build step resolved
chromium --headless --no-pdf-header-footer --print-to-pdf=deck.pdf "RoadShow Deck - share.html"
pdftoppm -png -r 100 deck.pdf slide
```

---

## New files in `docs/`

| File | What it is |
|---|---|
| `RoadShow Deck - present.html` | The deck with the thumbnail sidebar off, so the slide fills the screen. **Use this at the pod.** Open it, F11, click once on the slide, drive with `→`. |
| `RoadShow Deck.pdf` | Backup — 11 pages, 1920×1080, every build step resolved. |
| `presentation-script.md` | Run sheet for the Week 6 road show: shift times, the 10-minute round, the four-minute pitch, question bank. |
| `deck-changes.md` | This file. |

`RoadShow Deck - share.html` is unchanged in name and still the copy to send to people — the
sidebar makes it easier to navigate by thumbnail.

**Note on the sidebar:** the presenting copy stores its hidden-sidebar preference in whichever
browser opens it, so the share copy may also open without a sidebar afterwards. To restore it,
open the console (F12) and run `localStorage.setItem('deck-stage.railVisible','1')`, then
reload.

---

## Still open

**The A4 brochure.** The Week 5 explainer requires one — team number, company name, a picture of
the product, an illustration of an application scenario. Nothing in the repo covers it, and it
is the only thing visitors physically take away from the table.
