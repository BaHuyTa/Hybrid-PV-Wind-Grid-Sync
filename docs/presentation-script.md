# Road Show Run Sheet — Week 6

> **Superseded, 4 September 2026.** This is the run sheet for the roadshow as delivered on
> 2 September, when the design was DC-coupled with 3 kW of wind. After the product-owner meeting
> the system is AC-coupled (one DC link and one inverter per source) and the wind branch is 30 kW.
> The pitch below — "one shared bus, one inverter" — is what was said on the day, not the current
> design. See the README and `docs/wind-model-spec.md` for the current architecture.

**Wednesday 2 September 2026** · Team 1, Smart Grid Technologies · Product owner: Dr Mohammad Abuhilaleh

> **Read this first.** This is not a stage presentation. It is a trade show. You sit at your
> team's table, a handful of visitors stand around it, and you have **four minutes** to talk
> them through the project — three times, to three different groups. The brief is explicit:
> *"bring a laptop if you wish to show a slide or 2, but it is a conversation, not a long
> slide show."*
>
> The 11-slide deck is not the instrument for this. Two slides of it are.

---

## Your shift

| | |
|---|---|
| **Shift 1 · 3:10–3:40 pm** | **Hoang Khuc + Ba Huy Ta** — you present, 3 rounds |
| Shift 2 · 3:43–4:13 pm | Duc Pham + Aqib Mohamed Ameer present — **you visit 6 teams** |
| Shift 3 · 4:16–4:46 pm | Redhwan Ahmed + Belal Abu-issa present — **you keep visiting** |

You are on **first**, with Hoang. Nobody else from Team 1 is presenting in your shift — the
two of you carry the whole pitch, and you do it three times.

Both halves are graded. The rubric marks *"excellent roadshow presentations **and gave
meaningful feedback to other teams**"* — so the six teams you visit in shifts 2 and 3 are
worth as much as the three rounds you pitch.

---

## The 10-minute round

| Minutes | What | Who |
|---|---|---|
| **2:00** | Welcome — engage the visitors, find out who they are | both |
| **4:00** | Pitch — a conversation, with a slide or two | both, alternating |
| **2:00** | Q&A | whoever owns the answer |
| **2:00** | Visitor feedback — online form and post-its | them, while you reset |

Three of these back to back, 30 minutes, then you hand the table to Duc and Aqib.

**Round 2 and round 3 are not repeats — they are revisions.** You will learn something in
round 1. Fix it in the 90 seconds between rounds. That improvement loop is exactly what the
subject is assessing.

---

## Minute 0–2 · Welcome

Do not start pitching. Start a conversation — you need to know who is in front of you before
you choose which version of the project to tell them.

> **Hoang:** Hi — welcome to Team 1. We're Smart Grid Technologies. Who are you with?

> **Huy:** What's your team working on?

Then place yourselves in one line, and hand them something to hold:

> **Huy:** We're building a solar-and-wind power plant that plugs into the grid — entirely in
> simulation. Grab a brochure, and stop us any time. Genuinely, interrupt.

**Read the room in those two minutes.** Most visitors are from the health, genomics and data
teams — they are not power engineers, and the pitch below is already written for them. If you
happen to get GridBridge, Helios X, ZenithSolar or Firebreak — the other energy teams — you
can drop the analogies and go straight at the architecture.

**While they arrive:** laptop open at slide 4, screen angled *towards them*, brightness up.
Not on your lap. On the table, facing out.

---

## Minute 2–6 · The pitch

Roughly 4 minutes, alternating. Slide cues in **[brackets]**. Aim to be *finished* at 3:30 so
questions have room — the Q&A is where you actually win people over.

### 1 · The problem — Hoang · ~30 s · no slide

> The electricity grid is one shared 50-hertz wave, and every machine on it has to agree on
> where that wave is. Coal and gas generators hold that rhythm just by being heavy — the
> rhythm is a by-product of their spinning mass.
>
> Solar and wind don't have that. They connect through inverters — power electronics, no
> moving parts, no inertia — so they have to *measure* the rhythm and match it, thousands of
> times a second. As the heavy machines retire, that gets harder.

### 2 · What we're building — Hoang · ~50 s · **[slide 4, build it as you talk]**

**[→ press once per stage while you say it — the diagram draws itself left to right]**

> So this is our system. 5 kilowatts of solar **[→]**, 3 kilowatts of wind **[→]** — both
> feeding one shared 700-volt DC bus **[→]**. One inverter turns that back into clean
> grid-frequency AC **[→]**, and a protection relay disconnects it in under 2 seconds if the
> grid goes away **[→]**.
>
> Two sources, one bus, one connection to the grid. All of it in MATLAB and Simulink — no
> hardware, deliberately. It lets us test the failure cases you could never safely build on a
> bench.

### 3 · The decision we can defend — Hoang · ~25 s · same slide

> The one architectural call: **one shared bus instead of an inverter each.** One inverter,
> one phase-locked loop, one grid interface — instead of two of each fighting over the same
> connection point.

**[Handoff]**

> **Hoang:** Huy's been running the tests — he'll tell you what we found.

### 4 · What we've actually proved — Huy · ~70 s · **[slide 8]**

This is the part that separates you from a team reading out a plan. Slow down here.

> We're at week 6 of 12, so the honest answer is: one subsystem, tested properly.
>
> We wrote the tests first — an automated harness, 6 operating scenarios, 9 pass/fail checks,
> about 3 seconds a run. Then we put the solar array and its tracking algorithm through it.
>
> The tracker is good — it holds 98.8 to 100% of the power available. But the harness caught
> three things a visual check would have missed. The best one: on a falling-light ramp, the
> tracker took 100 steps, reversed direction 99 times, and made **zero net progress**. That's
> a textbook algorithm failure — and we found it in our own model, in week 6, instead of
> reading about it in a paper in week 11.
>
> So at halfway, the useful result isn't "it works". It's a list of things we know are wrong
> while there's still time to fix them.

### 5 · My part — Huy · ~35 s · no slide

Own something specific. This is your individual contribution, and the graders are looking for it.

> My subsystem is the wind side — turbine, generator, rectifier, into that shared bus.
>
> The thing I had to prove is that it *can't* interfere with the grid-side controllers. A wind
> gust from 8 to 12 metres per second takes 4.8 seconds to work through the rotor. The DC bus
> has to recover in 200 milliseconds, and the inner current loop in 2. That's three decades of
> separation — so whatever we find on the grid side is a real grid effect, not my model
> leaking into their result.

### 6 · Close and hand back — Huy · ~20 s

> The part we added ourselves: we're testing how *weak* the grid can get before our controller
> breaks — that's the bit nobody asked us for.
>
> What would you want to see from us at the final roadshow?

That last question is the close. It starts the Q&A, it gets them talking, and their answer is
free feedback for the PDLJ.

---

## Minute 6–8 · Q&A

One sentence, then stop. If they want more they'll ask.

**"Why one shared DC bus instead of an inverter each?"**
One inverter, one PLL, one grid interface — instead of two of each interacting. Two grid-tied
inverters on one connection point is a coupled control problem nobody asked us to solve.

**"Isn't 100% simulation a weakness?"**
It's what lets us test the failure cases. Islanding means deliberately killing the grid while
the inverter is exporting — you can't do that safely on a bench, and it's the behaviour
AS/NZS 4777.2 cares most about.

**"What have you actually measured, as opposed to planned?"**
One subsystem end to end: PV array plus MPPT, through a 6-scenario, 9-check harness. Tracking
holds 98.8–100% of available power, and the harness found three defects.

**"Why a diode bridge on the wind side, not an active rectifier?"** *(Huy)*
It makes the wind branch structurally identical to the PV branch — source, boost, bus — so
it's one converter model and one algorithm across both. An active front end would add a
machine-side current loop and a speed loop to the control pair's workload, and no success
criterion measures generator-side performance.

**"How do you know the source loops won't fight the grid-side loops?"** *(Huy)*
Measured, not assumed. 4.78 seconds for the rotor to settle, against a 200 ms bus spec and a
2 ms current loop. Three clean decades.

**"What if Perturb & Observe hunts under turbulent wind?"** *(Huy)*
Fallback is optimal torque control, T\* = k·ω². Flagged in the spec, not planned — we'd rather
find out from the harness than add a second algorithm pre-emptively.

**"Who owns the DC-link capacitor?"**
Integration — Hoang. Exactly one place owns C_dc, or the bus dynamics are wrong.

**"What's the hardest part from here?"**
Weeks 8 to 11 are one chain — PLL, then DC bus integration, then full system, then weak-grid
testing — and there's one buffer week. That's why every subsystem gets tested standalone
first.

**"What is SCR?"**
How far the microphone is from the speaker. Below about 3, the grid is weak enough that the
inverter's own output moves the voltage it's measuring. **[slide 10 if they're interested]**

**"Can I see it running?"**
Only if you have MATLAB already open and warm. Otherwise: "come back at the final roadshow" —
never boot Simulink in front of a queue.

---

## Minute 8–10 · Feedback, and the reset

They fill in the online form and write post-its. Meanwhile, in about 40 seconds:

1. **Reset the deck** — press `Home`, or reload at `#4`.
2. **Collect the post-its** — do not leave them for the next pair.
3. **One sentence to each other:** what to change in the next round.
4. Straighten the brochures, breathe, greet the next group.

---

## Between rounds — the improvement loop

After round 1, ask yourselves exactly two questions:

- Where did their eyes glaze over? Cut that sentence in round 2.
- What did they ask about? Move it *earlier* in round 3 — a question asked twice is a hole in
  the pitch.

Write both down straight after the shift. That is your PDLJ entry, and the rubric asks for
reflection tied to evidence.

---

## Shifts 2 and 3 — you are a visitor, and it is graded

Six teams. *"Gave meaningful feedback to other teams"* is what separates the top band from the
middle one, so brief descriptive comments are not enough.

For each team, leave a post-it with **one specific thing that worked** and **one question you
actually had**:

- ✅ *"The failure-mode demo made the risk concrete — what happens if the sensor drops out?"*
- ❌ *"Good presentation, well done."*

Teams you might want to see, since they are adjacent to ours: **GridBridge**, **Helios X**,
**ZenithSolar**, **Firebreak Energy System** (all Dr Abuhilaleh's teams too), and **Modular
Second Life Battery**.

Note one line per team as you go — six visits blur together within the hour, and you need them
for the PDLJ.

---

## The table

The brief asks you to own the pod: company name, colours, a brochure, QR codes, something to
pick up.

- **A4 brochure** — required. Team number, company name, a picture of the product, and an
  application scenario. *(Not built yet — see the note at the end.)*
- **Laptop** open at slide 4, facing the visitors, on `RoadShow Deck - present.html`.
- **The PDF backup** on the same machine, in case the browser misbehaves between rounds.
- **Post-its and a pen** on the table, and the feedback QR code visible.
- Company name to use consistently: **Grid Synchronization Pty Ltd**, Team 1.

---

## Pre-flight

- [ ] `RoadShow Deck - present.html` open, fullscreen, sitting on slide 4 (`#4`)
- [ ] Screen brightness up, laptop angled at the visitors, power plugged in
- [ ] Brochures printed and on the table
- [ ] Post-its and pen out; feedback QR visible
- [ ] Notifications off, phone silent
- [ ] You and Hoang have agreed who says what — run it once out loud before 3:10
- [ ] A watch or phone on the table where you can see it — the rounds are strictly timed
- [ ] Notebook for what visitors ask (this becomes your PDLJ entry)

---

## Which slides, and how to drive them

Use two. Three at most.

| Slide | When | Why |
|---|---|---|
| **4 · The system** | during "what we're building" | It builds left to right, one press per stage — it paces your sentences for you |
| **8 · What we have proved** | during the findings | The evidence slide; it is the reason to believe you |
| **10 · Our differentiator** | only if asked about weak grids | The microphone-feedback analogy lands fast, but it's optional |

`→` advances one build step, and pressing past the last step of a slide moves to the next
slide. `←` goes back. `Home` returns to slide 1. Adding `#4` to the URL opens straight at
slide 4 — that's your reset between rounds.

**Do not walk the whole deck.** Eleven slides is five minutes and fifty-one seconds of
talking, which is longer than your entire pitch window.

---

## The long version — for the final roadshow

The full 11-slide script still exists and is still good; it just isn't for a four-minute table.
Keep it for the end-of-session roadshow, where the format is likely to be a proper
presentation.

| # | Slide | Steps | Budget | Cumulative |
|---|---|---|---|---|
| 01 | Title | 1 | 0:10 | 0:10 |
| 02 | Why this matters | 5 | 0:34 | 0:44 |
| 03 | What we are building | 2 | 0:22 | 1:06 |
| 04 | The system | 6 | 0:52 | 1:58 |
| 05 | The three jobs | 4 | 0:32 | 2:30 |
| 06 | What "done" looks like | 8 | 0:28 | 2:58 |
| 07 | Where we are | 5 | 0:24 | 3:22 |
| 08 | What we have proved | 6 | 0:40 | 4:02 |
| 09 | Live demonstration | 1 | ~1:00 | 5:02 |
| 10 | Our differentiator | 6 | 0:26 | 5:28 |
| 11 | Risks, and what happens next | 6 | 0:23 | 5:51 |

The full per-beat script for those eleven slides is preserved in the run sheet page published
alongside this file, under **The long version**. Every line in it is drawn from the speaker
notes already embedded in the deck — press `→` at each marked point and the deck keeps pace.

---

## Showing the deck

One self-contained HTML file — fonts, scripts, images all embedded. No internet, no server, no
install. Double-click and it runs.

| File | Use |
|---|---|
| `RoadShow Deck - present.html` | **the table copy** — sidebar off, slide fills the screen |
| `RoadShow Deck - share.html` | sending to people; sidebar on for navigating by thumbnail |
| `RoadShow Deck.pdf` | backup — 11 pages, every build step resolved |

For a table, in a bright room, on a laptop:

- Open the presenting copy, press **F11** for fullscreen, **click once on the slide** so the
  page has keyboard focus, then drive with `→`.
- Add **`#4`** to the URL so every reload lands on the system diagram.
- Brightness to maximum, and angle the screen at the visitors rather than at you — at a table
  people read the screen from the side, and this deck is high-contrast enough to survive it.
- Don't export to PowerPoint: it would flatten the builds into static images and lose the
  motion on slide 4, which is the one doing work for you.
- Restoring the sidebar afterwards: open the console (F12) and run
  `localStorage.setItem('deck-stage.railVisible','1')`, then reload.

---

## Still missing

**The A4 brochure.** The explainer requires one: team number, company name, a photo or picture
of the product, and an illustration of an application scenario. Nothing in the repo covers it
yet, and it's the one physical thing visitors take away from the table.
