# Minimap Radar v2 — threat-aware radar rebuilt from the base up

Date: 2026-09-09 · Files: `scripts/ui/minimap.gd`, `scripts/ui/help_panel.gd`,
`tests/unit/test_minimap_radar.gd`, `tests/python/test_regress_minimap_radar.py`,
four evolved v1-era guards, `tests/run_tests.gd`.

## What the audit found (v1)

v1 was a 15 Hz snapshot radar:

1. **Snap-drawn tracks.** `_process` re-queried groups at 15 Hz and `_draw`
   painted each dot directly from the node's current `global_position`. A 5 m/s
   enemy therefore jumped ~0.8 m on screen every 66 ms — visible stepping, and
   no interpolation budget was left for anything smoother.
2. **Dead code.** `var _north_up := true` was declared and never read.
3. **No transitions.** Enemies appeared/disappeared in a single frame; there was
   no "newly spotted" cue and no death fade.
4. **No orientation context.** A wedge showed facing but no cone, so the player
   couldn't judge *which way is ahead* without counting pixels.
5. **No threat hierarchy.** All regular enemies were identical 2.5 px dots;
   nothing told you which contact was the immediate one; a boss fight looked
   the same as an empty arena until you noticed the big dot.
6. **Unconditional redraws.** `queue_redraw()` every discovery tick even when
   nothing on screen changed (idle arena → wasted 15 canvas invalidations/s).
7. **Unreached intent.** The header advertised "hazard rings" that were never
   drawn.

## Research (repeated web pass, 2026-09-09)

- **Radar orientation** (CS2 pro setups, multiple 2025/26 guides): a *fixed*
  (north-up) radar keeps a stable mental map; orientation is read from the
  player icon/wedge, and radar scale/zoom trade detail against overview. The
  dead `_north_up` in v1 was the abandoned start of exactly this — v2 makes it
  behaviour: north-up projection (already axis-aligned in v1) + a facing cone.
- **Radar information design** (ESL Katowice custom radar write-up): the wins
  were *firing indicators*, *view-direction indicators*, *priority emphasis*
  ("boost priority — always shown over the rest"), i.e. the radar's job is to
  make the important thing the *most visible* thing.
- **New-target pings** (PUBG "enemy spotted", Valorant pings): a newly spotted
  hostile gets a distinct pin + expanding marker so first contact is readable
  before the dot is tracked by eye.
- **HUD information hierarchy** (generalistprogrammer game UI/UX guide):
  minimap/radar is high-priority always-visible; dynamic elements must not add
  clutter; contrast + consistent placement matter more than quantity.
- **Frame-rate-independent smoothing** (lisyarus.github.io exponential
  smoothing): `pos += (target - pos) * (1 - exp(-rate*dt))` is the exact
  solution of the first-order smoothing ODE — correct for *any* `dt`, no
  jitter when `rate*dt > 1`. This is the same family this repo already uses
  for the camera (`CameraMath.exp_weight`), so the radar now eases with the
  same feel as the world camera.

## Design (v2)

**Decoupled cadences.** Group queries (the only expensive part) stay at 15 Hz
inside `_discover()`. The track *easing* and drawing run every frame, but
`queue_redraw()` is gated on `_dirty or _animating()`: an idle radar (no moving
tracks, no pings, no fades, no boss pulse, stationary player) issues zero
canvas invalidations. Roster changes are detected by a deep value compare of
the live list, so even the 15 Hz pass only repaints on real change.

**Pure, headless core.** Everything deterministic is static and node-free:

- `project_to_map()` — v1-pinned (centre + clamp-to-rim), now degenerate-safe
  for `half <= 0` / `radius <= 0` / NaN.
- `track_position(current, target, delta, rate)` — the canonical exponential
  step; hard-follow for `rate <= 0`, no-op for `delta <= 0`, NaN-safe.
- `ping_progress(elapsed_ms, duration_ms)` — 0..1 spawn-ping window.
- `blink_alpha(urgency, phase_ms)` — deterministic 2.5 Hz urgency pulse for
  expiring pickups.
- `wedge_points(center, facing, length, spread)` — degenerate-safe triangle.
- `advance_tracks(previous, live, delta, now_ms, ...)` — the state machine:
  live-with-track eases to truth (alpha restores), live-without-track spawns at
  truth with `born_ms` (starts the ping), stale tracks hold last position and
  fade at `1/0.35 s`, garbage entries (non-dicts, bad ids, NaN) are ignored,
  duplicate ids collapse, and a 96-slot cap evicts stalest-first then oldest.
  Deterministic for identical inputs — pinned by unit tests.

**Rendering (per-frame, gated).**

- North-up disc, rim, quarter + 80 % range rings (v1 look preserved).
- Player wedge (instant — the one intentional direct read) + **70° facing cone**
  at 10 m world range: "where I'm looking" at a glance.
- **Spawn ping**: expanding ring, 4→20 px over 1.2 s, on every newly spotted
  enemy/elite/boss (never pickups).
- **Death fade**: 0.35 s alpha-out, holding last seen position.
- **Nearest-threat emphasis**: closest live enemy (world distance) gets a white
  ring.
- **Boss danger state**: while `BossController.BOSS_GROUP` is non-empty the rim
  pulses red at 1.4 Hz and the boss dot grows a pulsing halo (ESL-style
  priority emphasis).
- **Pickup urgency**: pips pulse 0.35..1.0 alpha during the final 25 % of
  `PickupConfig.lifetime`.
- Elite ring, boss size, and colour coding carry over from v1.

**Wiring.** Same public surface: `class_name Minimap extends Control`,
`arena_half`, 140×140 minimum, `project_to_map` semantics. Arena still resolves
via `Arena.ARENA_GROUP` with the legacy `WorldRoot/Arena` path fallback inside
`_find_arena()` (QA-audit contract preserved). Group constants are the shared
ones (`EnemyBase.TARGET_GROUP`, `BossController.BOSS_GROUP`,
`Pickup.PICKUP_GROUP`). Facing is Godot's −Z forward, projected axis-aligned.
Help-panel legend updated to the new vocabulary (cone, closest-threat ring,
spawn rings, boss rim, expiring pips).

## Testing

- `tests/unit/test_minimap_radar.gd` (registered in `tests/run_tests.gd`):
  projection pins, frame-rate independence (2×0.1 s ≡ 1×0.2 s), no-overshoot
  convergence, NaN safety, ping window, blink phase values, wedge geometry,
  and the full `advance_tracks` contract (spawn/ease/fade/drop/respawn/junk/
  dedupe/cap/determinism).
- `tests/python/test_regress_minimap_radar.py`: shape guards — dead
  `_north_up` gone, 15 Hz appears only as the discovery constant, exponential
  smoothing pinned (not a raw `dt` lerp), redraw gating pinned, group queries
  out of the per-frame and draw paths, threat features present, −Z facing,
  NaN guard count, legend + suite registration.
- Evolved v1-era guards (intent preserved, names updated):
  `test_regress_arena_guards.test_minimap_throttled`,
  `test_regress_qa_release_audit.test_minimap_refresh_has_no_bare_path_lookup`,
  `test_regress_top5_hardening.test_minimap_caches_arena`,
  `test_regress_visuals_ring_and_effect.test_minimap_radius_clamped`.

Honest caveat: the Godot runtime suite still only executes in CI (no binary in
this sandbox); everything above is verified via gdparse/gdlint + the 528-test
Python gate + desk simulation of the unit-suite math.
