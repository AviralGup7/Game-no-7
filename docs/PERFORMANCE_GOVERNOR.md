# Performance Governor (adaptive quality scaling) — design & research notes

**Scope:** `scripts/utilities/performance_monitor.gd` and its wiring in
`scripts/main/main.gd`, `scripts/ui/ui_root.gd`, `scripts/ui/settings_panel.gd`,
`scripts/save/settings_data.gd`. Rebuilt 2026-09-09 after an audit found the old
monitor was the weakest subsystem in the game: a naive FPS-average governor whose
results were discarded, whose opening tier ignored the player's saved quality,
and whose "ultra" tier was unreachable (the settings schema silently dropped it).

Behavioural contract: `tests/unit/test_performance_monitor.gd` (deterministic,
pinned clock). Source-shape guards: `tests/python/test_regress_performance_governor.py`.

---

## What was weak (with evidence)

| # | Weakness | Evidence |
|---|----------|----------|
| 1 | **"ultra" tier unreachable**: monitor supports tiers 0–3, but `SettingsData.set_graphics_quality()` accepted only low/medium/high (silent drop → "medium"), and the settings panel offered only three options. The `&"ultra"` branch in `ui_root.gd` was dead code. | `settings_data.gd` whitelist; `settings_panel.gd` tier list; `ui_root.gd` mapping. |
| 2 | **Opening tier ignored the save**: `main.gd` created the monitor with no configuration; it hardcoded `TIER_HIGH`. A phone that had saved "low" (or that auto-scaled to low) opened every new run at high quality and re-lagged for seconds. | `main.gd` `_create_run_systems`; `performance_monitor.gd` `var _tier: int = TIER_HIGH`. |
| 3 | **Saved tier stomped on every save**: `ui_root._apply_settings` ran `monitor.set_tier(saved_quality)` on *every* `settings_changed` — so saving a volume change mid-run re-asserted the saved tier and clobbered whatever the auto-scaler had found. | `ui_root.gd` `_apply_settings`. |
| 4 | **Auto-scaled tier never persisted**: no feedback loop from governor → save; each launch re-derived quality from scratch. | no persistence call anywhere in the monitor. |
| 5 | **Naive statistics**: arithmetic mean of *FPS* over 60 samples. FPS is the nonlinear inverse of frame time (alternating 30/90 fps averages to "60"), and the mean hides the stalls players actually feel. No percentile, no hitch count. | old `get_average_fps()` + `DOWN/UP_THRESHOLD` on the average. |
| 6 | **Absolute thresholds**: 45/57 fps constants unrelated to the tier's own frame budget. A 30 fps tier is *designed* to run at 33.3 ms — absolute rules misread healthy capped tiers as failing and cascade to the floor, from which recovery is impossible (the cap forbids the frame times the upgrade rule demands). | old `DOWN_THRESHOLD := 45.0`, `UP_THRESHOLD := 57.0`. |
| 7 | **O(n) per frame**: `PackedFloat32Array.remove_at(0)` + full re-sum of the window, every frame. | old `_push_sample`/`get_average_fps`. |
| 8 | **No warmup, no window clear on tier change, no session-cap awareness**: load spikes at run start could trigger instant downgrades; decisions ran on stale samples from the previous tier; a player-selected 30 fps session cap could be silently overridden by a tier change (`Engine.max_fps = 60/0`). | old file had none of these. |
| 9 | **Docstring over-promised**: "steps the quality tier down (particle counts, shadows, MSAA hints)" — MSAA was never touched, even though it is the cheapest high-impact GPU lever on the mobile renderer. | old docstring vs. code. |

---

## The rebuild, and where each idea comes from

The governor now decides on **frame time** against a **per-tier budget**, with
**hysteresis**, **warmup**, **window clears**, and **persistence** of what it
settles on. Every design point below is grounded in published practice for
adaptive quality scaling (AQS) / dynamic resolution scaling (DRS); sources in
the [research log](#research-log).

1. **Frame time, not FPS.** Frame time is linear (budget vs. actual); FPS
   averages flatter mixed workloads. Frame-pacing literature treats the
   percentile frame time and "1% low / 0.1% low" as the real smoothness
   metrics — "average tells you nothing; your 99th percentile reveals
   worst-case performance" [CapFrameX/pacing literature, S1-S4].
2. **Relative thresholds — the single most important fix.** AQS systems that
   use absolute frame-time rules ("degrade when the average exceeds 18 ms")
   read a healthy 30 fps capped tier as failing, step down again and again,
   and "arrive at Minimal within seconds" with no way back up, because the
   tier's own cap forbids the frame times the recovery rule demands [S5].
   Here: `budget_ms(tier) = 1000 / effective_target_fps(tier)`; every gate is
   a *ratio* against that budget, so holding the designed rate reads as
   healthy, and a capped 30 fps tier can still earn its way back up.
3. **p95 + hitches, not just the mean.** "The 95th percentile frame time is
   more useful than the average, because it captures the stutters players
   actually notice" [S5]. Spiky workloads (recurring stalls, ok average) are
   caught by the hitch count: frames beyond **2× budget** (the conventional
   "spike" definition [S1-S4]); two+ hitches plus a stretched tail (p95 ≥ 1.5×)
   is the "spiky" downgrade gate, alongside the "sustained" gate (avg ≥ 1.15×
   and p95 ≥ 1.35×).
4. **Hysteresis: down fast, up cautiously.** "Without hysteresis, adaptive
   quality systems oscillate between tiers and produce a worse experience than
   a fixed low setting. Downgrades happen immediately when thresholds are
   breached; upgrades happen cautiously" — typically tens of seconds of stable
   performance before an upgrade [S5]. DRS literature is explicit: "introduce
   hysteresis so the system only scales up after sustained headroom, not
   instantly after a single easy frame. This prevents visible pumping" [S6].
   Here: downgrade needs **two consecutive sustained-bad 0.5 s decision ticks**
   (~1 s of evidence); upgrade needs **15 s of stability since the last tier
   change** plus a clean window; a 5 s cooldown separates any two steps (the
   pre-existing value, kept).
5. **Clear the window on every tier change** "so the next decision is never
   made on stale samples" [S5] — `_change_tier()` resets the ring, streaks,
   and the stability timer.
6. **Rate-capped tiers hide headroom.** A device that could hold 120 fps still
   shows 16.7 ms frames at a 60 fps cap — the cap is the limiter, not the
   hardware. "Where only frame pacing is available it steps up speculatively
   instead" [S5]. Here: when the window is *at the cap* (avg ≥ 0.95× budget),
   the upgrade gate tests **flat pacing** (p95 ≤ 1.1× budget, zero hitches)
   instead of average headroom the cap would forbid; uncapped tiers keep the
   strict headroom gate (avg ≤ 0.8×, p95 ≤ 0.9×, no hitches).
7. **Warmup.** Fresh runs absorb load spikes (scene build, first shader
   compile); no auto-steps for the first 3 s (samples still accumulate).
8. **Persist what you settle on.** AQS practice treats the settled tier as the
   new baseline for the device [S5, S7]; the governor calls an injected
   `Callable` seam on each *auto* step (manual user changes never persist
   through the governor — the user's explicit choice is what gets saved).
   `main.gd` wires the seam to `SaveManager`, so the next launch opens at the
   tier the device already proved it can hold. The monitor itself stays free
   of autoload identifiers so headless suites can compile it under `--script`
   (the repo's load-order contract).
9. **Session cap survives tier changes.** The player's Settings FPS cap
   (30/60/120/unlimited, applied to `Engine.max_fps`) can only *tighten* the
   governor's cap and budget — a tier change can lower `Engine.max_fps`,
   never raise it above the player's choice.
10. **MSAA as a real actuator.** Tier knobs: LOW = 30 fps cap, MSAA off,
    shadows off, glow off, reduced fog; MEDIUM = 60 fps, MSAA 2× (the project's
    shipped default), shadows 1024; HIGH = project/session cap, MSAA 4×,
    shadows 1024, glow; ULTRA = project/session cap, MSAA 4×, shadows 2048,
    glow. 4× is the ceiling: the engine docs call 8× MSAA "unlikely to run
    smoothly on mobile GPUs" and note 2× is the mobile-friendly level [S8].
    Applied live via `Viewport.msaa_3d` on the root viewport [S9]; restored
    from the project setting in `_exit_tree()`, the same good-citizen
    teardown the fps cap already required.

### What is deliberately NOT in scope

- **Thermal state.** Android's ADPF thermal API (`PowerManager.
  getCurrentThermalStatus`, `getThermalHeadroom`) is the right input where
  available [S10], but Godot 4.4 exposes no built-in thermal API — reaching it
  needs a native Android plugin, which conflicts with this project's
  "no permissions, no extra native surface" export posture. Frame time already
  reflects throttling: "on older versions, you need to infer [thermal state]
  from frame time trends" [S5]. Revisit if a Godot-side thermal plugin becomes
  standard.
- **Dynamic resolution.** The mobile renderer's `viewport_set_scale_3d` would
  be a useful second actuator, but resolution scaling blurs text/UI on small
  phone screens and the current knobs (fps cap, MSAA, shadows, particles,
  live-enemy count) already cover the budget. Kept out to avoid scope creep.
- **Memory-based initial tier.** Engine memory (`OS.get_static_memory_usage()`,
  in MB) is exposed in the debug snapshot as telemetry; it does not gate
  behaviour (the governor measures, and persistence learns, what the device
  actually does). 4.4 has no total-system-RAM getter, and string dispatch is
  banned by the typed gate, so the probe stays on the typed engine API.

---

## Tuning constants (all at the top of the file)

| Constant | Value | Meaning |
|----------|-------|---------|
| `RING_SIZE` | 240 | ~4 s at 60 fps; O(1) push, O(n log n) percentiles at decision cadence only |
| `DECISION_INTERVAL_SECONDS` | 0.5 | decision tick cadence |
| `WARMUP_SECONDS` | 3.0 | no auto-steps after a fresh run |
| `MIN_SECONDS_BETWEEN_STEPS` | 5.0 | cooldown between any two steps (pre-existing contract) |
| `UP_STABILITY_SECONDS` | 15.0 | clean stretch required before an upgrade |
| `DOWN_AVG_RATIO` / `DOWN_P95_RATIO` | 1.15 / 1.35 | "sustained" downgrade gate |
| `DOWN_HITCH_MIN` / `DOWN_SPIKE_P95_RATIO` | 2 / 1.5 | "spiky" downgrade gate |
| `UP_AVG_RATIO` / `UP_P95_RATIO` | 0.8 / 0.9 | upgrade gate (uncapped tiers) |
| `AT_CAP_AVG_RATIO` / `UP_P95_AT_CAP_RATIO` | 0.95 / 1.1 | upgrade gate (rate-capped tiers) |
| `HITCH_BUDGET_MULT` | 2.0 | frames beyond 2× budget are hitches |
| `MIN_SAMPLES_FOR_DECISION` | 30 | minimum ring fill before a decision is trusted |

## Behavioural invariants (pinned by the unit suite)

- Warmup holds; sustained 3×-budget frames walk HIGH→MEDIUM→LOW and stop at
  the floor; each auto step persists its tier (`["medium","low", ...]`).
- A flat 60 fps stream upgrades exactly one tier per 15 s stability window,
  capping at ULTRA; a 30 fps session cap is never raised above by any tier
  change; manual `set_tier` emits once, is silent on repeat, never persists.
- p95 of 1..100 ms is 95 (nearest-rank); the ring caps at 240 samples keeping
  the newest frames; NaN/negative/too-large samples are dropped.
- A healthy at-cap tier does not trigger a step inside the stability window;
  a spiky workload (ok average, recurring hitches) does step down; a single
  live hitch blocks an upgrade until it ages out of the window.

---

## Research log (2026-09-09, repeated searches as required)

- **S1** Frame pacing / 1% low / 0.1% low metrics and "spike > 2× average"
  convention — PresentMon-based tooling literature (CapFrameX, FrameView,
  RTSS): https://unstore.io/discover/best-apps-for-frame-pacing-measurement-desktop/
- **S2** Percentile frame time as the smoothness metric:
  https://thefpstester.com/tools/frame-pacing-checker
- **S3** "95th percentile within 2 ms of average / no spikes above 2×"
  acceptance bands: https://bottleneckcalculator.us.com/knowledge-base/bottleneck-basics/frame-pacing-vs-fps-the-secret-to-smoothness/
- **S4** 1% low / 0.1% low as the industry-standard pacing metrics:
  https://mycalcbuddy.com/gaming/frame-time-calculator
- **S5** AdaptiveQualityManager architecture (RuneScape Mobile / Domi Online /
  Nova Blast): relative-not-absolute thresholds and the "cascade to Minimal,
  recovery impossible" failure mode; hysteresis with 30–60 s stability before
  upgrades; p95 over average; clearing the profiler window on every
  transition; speculative step-up where only pacing is available:
  https://github.com/Ocean-View-Games/unity-mobile-performance-architecture/blob/main/docs/mobile-optimisation-guide.md
  and https://oceanviewgames.co.uk/blog/posts/managing-thermal-throttling-unity-mobile
- **S6** DRS hysteresis ("only scales up after sustained headroom … prevents
  visible pumping"): https://pulsegeek.com/articles/dynamic-resolution-scaling-for-streaming-games/
- **S7** Tiered/adaptive scaling as standard mobile practice:
  https://redappletechnologies.medium.com/mobile-game-optimization-guide-fps-memory-battery-and-load-time-0e5ab3160c18
- **S8** Godot 3D antialiasing guidance (MSAA levels, 2× mobile-friendly,
  8× "unlikely to run smoothly on mobile GPUs"; `msaa_3d` setting):
  https://github.com/godotengine/godot-docs/blob/master/tutorials/3d/3d_antialiasing.rst
- **S9** Live per-viewport MSAA in Godot 4: `Viewport.msaa_3d` property /
  `RenderingServer.viewport_set_msaa_3d(rid, msaa)` (MSAA enum 0/2/4/8):
  https://forum.godotengine.org/t/first-parameter-of-viewport-set-msaa-3d/45721 and
  https://www.reddit.com/r/godot/comments/xvgl3r/how_to_change_graphic_settings_on_runtime_godot/
- **S10** Android ADPF thermal API (why thermal state is *not* wired: no
  Godot-side API; frame time is the proxy):
  https://developer.android.com/games/optimize/adpf/thermal
- **Godot runtime knobs verified:** `Engine.max_fps` is the runtime cap and
  `application/run/max_fps` is read once at startup (project doc note);
  `ProjectSettings.get_setting_with_override()` for feature-scoped values:
  https://docs.godotengine.org/en/4.4/classes/class_projectsettings.html
