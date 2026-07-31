# Large Print Hitori

A logic puzzle built for older adults. Shade out the repeated numbers until no
number appears twice in any row or column.

**No timers. No guessing. No account. Works with the network switched off.**

---

## What Hitori is

You are given a grid of numbers. Shade cells out until:

1. **No number appears twice** in any row or column, counting only the cells
   you did *not* shade.
2. **No two shaded cells touch** edge to edge. Corners are fine.
3. **All unshaded cells form one connected group** — you can walk between any
   two of them without crossing a shaded cell.

Rule 3 is what makes Hitori different from every other puzzle in this
portfolio. It is a *global* constraint: whether a cell may be shaded can
depend on a cell on the far side of the board.

---

## Why this exists

| Decision | Reason |
|---|---|
| Opens at **1.15× text scale** | The app opens large. Shipping at 1.0 and expecting people to find a settings screen is the mistake every competitor makes. |
| **Elapsed clock only, never a countdown** | Time pressure is the single most common complaint from older players. |
| **Every puzzle is solvable without guessing** | Verified by computer on every puzzle. "I got stuck and had to guess" is indistinguishable, to the person holding the phone, from "this app is broken". |
| **Three cell states, not two** | Hitori players ring the cells they have *proved* must stay. "Not yet decided" and "definitely stays" are different facts, and confusing them is how you lose track. Most digital Hitori apps offer only shade/unshade. |
| The number stays visible on a shaded cell | Players re-check what they shaded constantly. Hiding it would force an undo just to look. |
| **Drag to paint** | Precise repeated tapping is exactly what arthritic hands struggle with. |
| Mistakes shown by **colour + shape + shake** | Never colour alone. |
| Hints **name the pattern** | A hint that just shades a cell teaches nothing and leaves you equally stuck next time. |
| No cognitive or medical claims, anywhere | Lumosity paid a **$2M FTC settlement** for exactly that kind of copy. |

---

## The engine

Pure Dart, no Flutter imports, so it unit-tests on a bare VM. Two invariants
are checked on **every** emitted puzzle:

1. **Exactly one solution**, verified by an independent solution counter.
2. **Solvable by pure logic**, with no trial-and-error branch. Strictly
   stronger than uniqueness, and the one players actually feel.

Measured over 240 puzzles across all four sizes:

| Metric | Result |
|---|---|
| Uniquely solvable | **240 / 240** |
| Solvable with no guessing | **240 / 240** |
| Logic result matches intended answer | **240 / 240** |
| Generation failures | **0** |
| Worst generation time | **19 ms** |

### Two things measurement caught that guessing would not

**Shading density is everything, and it is counter-intuitive.** Generation
failed 400/400 attempts at 5×5. Adding stage counters showed every rejection
was *"multiple solutions"* — never a failed construction. Sparser puzzles are
*harder* to generate, because with few shaded cells there is not enough
evidence to pin the answer down:

| density | 5×5 | 6×6 | 7×7 | 8×8 |
|---|---|---|---|---|
| 0.16 | 0/120 | 0/120 | 0/120 | 0/120 |
| 0.20 | 0/120 | 0/120 | 0/120 | 0/120 |
| 0.24 | 12/120 | 10/120 | 1/120 | 0/120 |
| 0.28 | 65/120 | 46/120 | 61/120 | 46/120 |

My targets were 0.20–0.26 — squarely in the dead zone.

**The solver deduced nothing at all.** Once generation worked, every puzzle
required 100% guessing. `propagate()` only fired on cells *already* marked, so
from a blank grid nothing triggered — it decided 0 of 25 cells. Adding the
three techniques that bootstrap a real Hitori solve (**triple**, **sandwich**,
**pair**) took it from 0/60 to 54/60, and enforcing guess-free as a hard
generation invariant took it to 60/60.

---

## Accessibility

* Text scale slider 0.85–1.6 with a **live preview** while you drag.
* High-contrast mode: pure black on white, heavier grid lines.
* Dark mode.
* The "keep" ring differs from the shading **in hue, not just lightness**, so
  the two states survive colour-blindness — asserted by test at >40° apart.
* The number on a shaded cell clears 4.5:1 against it, also asserted by test.
* Auto-ringing the neighbours of a shaded cell is forced by rule 2, so it can
  never be wrong — and it undoes as **one** action, not one press per cell.
* Screen-reader labels throughout; the timer announces *"there is no time
  limit."*

## Audio

Ten sound effects and two music tracks, all **CC0** (Kenney *Interface
Sounds*, MintoDog *Cozy Puzzle*). Music **defaults to off** — audio that
starts unasked is an uninstall trigger for this audience.

Every file was measured with `ffprobe` before shipping, which caught the same
trap Game #1 hit: Kenney's `click_002` and `click_004` are both **10 ms** long
and silent in practice. Provenance and the duration table are in
[`ATTRIBUTION.md`](ATTRIBUTION.md).

---

## Daily puzzle

Derived from a hash of the calendar date, so everyone worldwide gets the same
puzzle with **no server and no account**. Difficulty ramps Monday → Saturday
following newspaper convention, and eases off on Sunday.

The date hash is hand-rolled rather than using `Object.hash`, which is
explicitly not stable across Dart versions — using it would silently change
everyone's puzzle on an SDK bump.

---

## Building

```bash
flutter pub get
flutter test                 # 65 tests
flutter analyze              # clean
bash tool/verify_assets.sh   # audio integrity, incl. audibility floor
python tool/generate_icons.py
flutter build apk --release --target-platform android-arm64
```

Full toolchain setup, verified artifact sizes, and the four build failures
that recur on low-memory machines are documented in
[`RELEASE.md`](RELEASE.md).

## Status

Analyzer clean, 65 tests passing, release APK (21.7 MB) and Play bundle
(47.9 MB) both building.

**Not yet run on a physical device.** See `RELEASE.md` for the four blockers
before this can be published — the release build is still debug-signed and
still carries Google's AdMob test IDs.

## Licence

MIT © 2026 Aviral Gupta. See [`LICENSE`](LICENSE).
