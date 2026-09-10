# Android performance / stability audit

Date: 2026-09-08. Baseline: `375137151fc3cf63a9034c1ff3f4c29b7a566a37`.
Engine target: Godot **4.4.1**, Android ARM64, Mobile renderer.

## HD realism pass delta (same date)

The presentation overhaul below keeps the Mobile renderer but raises quality:
**2× MSAA, 8× anisotropic filtering, 2048px high-quality PCF directional
shadows, glow, exposure/contrast, per-arena 1K HDRI panoramas (IBL) and four
flickering torch omni lights (no shadows).** No SSAO/SSR/volumetrics are enabled.
Assets grew 222 → 239 locked files (35.05 → 45.63 MiB): 8 photo-PBR PNGs, 4
JPGs, 3 HDRIs and 2 licence notices. `HdMaterials` duplicates one shallow
material per mesh surface at mount time (bounded, no per-frame allocation).
Frame-time impact is unmeasured — the pending device matrix below still applies
(Mobile renderer + MSAA + HDRI at high native resolution are the costs to watch).

## Verification status — not an Android certification

**Runtime and device measurements are blocked in this workspace.** No Godot,
JDK, Android SDK, export templates, `adb`, emulator, or attached Android device
was found. Download attempts for the official pinned Linux Godot binary through
GitHub and the official download endpoint failed with TLS/connection errors at
the download hosts. `scripts/build_android.sh` and the new profile launcher were
attempted and fail explicitly at the missing-engine prerequisite.

Consequently, no cold-start milliseconds, FPS improvement, GPU draw-call reduction,
peak RSS/PSS, APK size reduction, thermal result, or successful Android export is
claimed. GDScript grammar parsing is **not** Godot's semantic compilation or execution.
The runtime probe below is added but **has not been executed** here.

### Checks actually executed

| Check | Result |
|---|---|
| Baseline Python tests | 502 passed |
| After-change Python tests | 513 passed (11 new structural guards) |
| Resource validator | 110 scene/resource files passed |
| Asset structure/dependencies | 81 models, 79 PNGs, 31 audio files, 2 fonts passed |
| Locked asset integrity | 222/222 files verified; 35.05 MiB approved downloads unchanged |
| Changed GDScript + new probe grammar | Passed `gdparse` (gdtoolkit); engine compilation pending |
| Profile launcher shell syntax | Passed `bash -n` |
| Whitespace/patch integrity | Passed `git diff --check` |
| Cold startup / gameplay / transitions / restarts | Runtime probe prepared; blocked by missing Godot |
| Android export | Attempted; blocked by missing Godot (SDK/JDK also absent) |
| Low/mid-range Android, thermal/battery soak | Not available; must run on hardware |

Raw local validation logs are under ignored `build/perf/`; they are not shipped or
committed. Test-suite duration is not used as a game-performance metric.

## Changes and before/after observations

The quantities below are **source-derived operation/allocation counts**, not device
benchmarks. They describe eliminated work and ownership errors that do not require
speculating about GPU speed.

| Area | Baseline | After |
|---|---|---|
| Player model startup | Bounds helper requires `Node3D` but recursively receives imported `AnimationPlayer` / other `Node` children, causing invalid typed calls | Accepts `Node`; only spatial nodes contribute transforms |
| Enemy feedback | Reads/tweens nonexistent `Node3D.modulate` on spawn and hits; transient tweens can stack on the same properties | One private reusable 3D flash material; no invalid property access; one active transient feedback tween per actor; cancelled scale pulses cannot remain partially expanded |
| Shipped audio startup | Generates 17 SFX and 5 music loops, then overwrites them with the approved library in Main | Registers approved audio before fallback; **0** procedural SFX/music generation with the complete shipped catalogue |
| Music synthesis work | Five × 6 seconds × 22,050 samples = **661,500 sample iterations**, plus 661,500 PCM byte conversions; 661,500 bytes of final 8-bit PCM and 2,646,000 bytes of cumulative float scratch payload | This discarded music synthesis is eliminated; compressed Ogg streams, cue aliases, looping and fallback algorithms are unchanged |
| VFX ownership | First burst allocates an unused, unparented `GPUParticles3D` template in addition to the owned pool. A Node is not reference-counted, so each used director leaks one emitter and its resources on teardown | No detached template. Every constructed emitter belongs to the director's bounded pool and is freed with it |
| Invalid projectile scene | Rejected non-Projectile root is abandoned once per pool slot; default pool has 48 slots | Rejected root is explicitly freed before creating the existing fallback |
| Projectile/pickup tint | One new `StandardMaterial3D` per launch/drop even though the node is pooled | At most one tint material per pooled object, reused with the same color/emission values; different objects do not share mutable tints |
| Damage text | Copies active Array each animated frame and searches by Dictionary for each expiration | Reverse-index iteration/removal: no active-array copy, no per-expiration search; survivor order and lifetime unchanged |
| Android frame ceiling | Startup has no application cap; high/ultra tiers explicitly restore unlimited rendering (can follow 90/120 Hz displays) | Android project cap 60; high/ultra respect it. Low tier remains 30; persistent menus recover the project cap after world teardown |
| Export resources | `all_resources` also includes test scenes/scripts/fixtures and validation tooling | Explicit `tests/*,tool/*` exclusion; dynamic runtime assets, data, manifests and licences retained |

The PCM figures are cumulative payload calculations, **not measured peak-memory
savings**. Asset decoding/import, allocator overhead, retained audio resources and
engine caches also affect startup memory.

### Behavior boundaries

No enemies, weapons, arenas, balance values, rewards, AI transitions, combat queries,
spawn ordering, collision masks, physics cadence, status durations, save schema,
input mapping, or gameplay content were changed. Physics stays **60 Hz**, with the
existing six-step per-frame catch-up limit. Flash colors and durations, damage text
lifetime, particle counts and pool caps are retained. The invalid 2D-style enemy
flash is implemented through a valid 3D overlay, detached when transparent; visual
parity/readability needs renderer validation. Rapid overlapping feedback now replaces
rather than accumulates transient tweens.

Audio precedence remains **approved library > data/audio > procedural**. Registration
moves into `ContentRegistry.refresh_all()` so synthesis only fills genuinely missing
cues, and Main no longer registers the same library a second time. No audio bytes,
variant choices, pitch policy, gain policy, playback timing, or synthesis algorithms
were edited.

## Inspection coverage and intentionally deferred work

The script inventory contains 139 GDScript files and 28 explicit `_process` /
`_physics_process` implementations (before this patch). Inspection followed the main
composition/state loop into its live dependencies rather than treating every helper
named `_validated_*` as an active safeguard.

### CPU, callbacks, timers, signals, coroutines

- Player and enemy movement/combat run at the fixed physics cadence. Target selection
  is attack-driven, not a global every-render-frame scan. Navigation retargeting is
  interval-based (normally 0.2s). No AI tick-rate or targeting changes without profiles.
- `StatusManager` and `ArenaHazards` were this file's two "plausible busy-wave cost, left
  alone" items; both have now been measured and fixed rather than excused. Status queries
  (move speed, outgoing/incoming damage, stun/root, shield pool) are cached folds
  invalidated by an application, a removal, an absorbed shield layer and the tick in which a
  duration crosses zero — one fold per entity per tick at most, with
  `recomputes`/`aggregate_reads` counters in `get_debug_snapshot()` so the cache is testable
  — the tick reuses two scratch arrays instead of allocating `keys().duplicate()`,
  config validation moved to load, and an idle manager is not ticked at all. Hazards went
  from gathering and filtering the player/enemy groups per hazard per tick to one lazily
  built snapshot shared by the set, bucketed in a `PackedInt32Array` grid, with per-hazard
  scan cadence (`HazardConfig.scan_interval`) and no victim query at all for a periodic
  pulse between bursts. See `docs/ARCHITECTURE.md` ("Status effects", "Arena hazards").
- HUD weapon refresh (0.15s), minimap (15Hz), and skill-bar refresh are already
  throttled. Ring fades and muzzle flashes disable processing while idle. Feedback
  mesh traversal is now cached on first use after the rig mounts.
- Spawn pacing uses an owned Timer; saves use a debounced Timer. Status tick loops
  have a bounded catch-up budget. No accumulating `await create_timer()` hot loop
  was found; `SceneRouter` has a one-frame coroutine for its routing flag.
- Most EventBus subscribers are tree-owned and disconnect on destruction. The probe
  checks enemy-killed listener counts across rebuilds. SceneRouter's full scene-swap
  seam is not the normal run path; gameplay uses persistent Main + world rebuilds.
- `PerformanceMonitor` scans a bounded 60-sample window and uses frame-based quality
  streaks. Its low-tier 30 FPS cap cannot satisfy the 57 FPS upshift condition, so
  automatic recovery from low remains an existing limitation. Do not claim its
  `particle_budget_scale()` alone reduces particle counts: EffectDirector does not
  currently consume that hint. No adaptive-quality redesign was made without hardware.

### Loading, instantiation, object lifetime and allocation pressure

- ContentRegistry synchronously scans `.tres` directories and retains config/scene
  resources, including enemy rigs, during startup. Main preloads player/spawner
  scenes. Threading this startup would require a loading-state contract for UI and
  autoload consumers; blindly moving it to a worker risks use-before-ready failures.
- Model mounting instantiates animated scenes and walks mesh bounds. Decorator scenes
  are cached per run; pickup visuals are cached per pooled pickup. Enemy creation
  is paced (initial burst 3, then Timer), not fully pooled. Do not add an unbounded
  model cache or prewarm every rig to trade stutter for OOM without memory captures.
- Projectiles prewarm 48 nodes. Pickups default to 32 nodes / 24 live. VFX remains
  capped at 10 bursts / 14 rings; floating labels at 32. These are already bounded.
- World rebuild queues old children for deletion while assembling replacements. That
  can temporarily overlap old/new scene memory and is a device-profile target. No
  unsafe immediate frees from combat/physics callbacks were introduced.
- GDScript Resources/RefCounted use reference counting, while Nodes require explicit
  ownership/freeing. The two detached-Node paths were real lifetime problems, not
  presumed managed-GC pauses. Other avoidable hot allocations were limited to the
  pooled tint materials and damage-number iteration addressed above.
- Run analytics retains 64 summaries; combat log is bounded. No unbounded log history
  was found there. Debug diagnostic formatting/printing can still distort gameplay
  timing; compare like-for-like builds and use release builds for thermal measurements.

### Texture/audio memory and rendering

- The 79 standalone PNGs represent **51,535,284 bytes (~49.15 MiB)** if all were
  resident as base-level RGBA8. This is only a dimension-based upper-format estimate:
  it excludes embedded rig textures/mips and does not imply simultaneous residency.
  Largest standalone textures are 1024×1024. Source downloads remain checksum-locked.
- Embedded glTF images use Basis Universal; ETC2/ASTC import is enabled. Standalone
  3D texture import/mip behavior still requires a fresh Godot import to inspect the
  actual cache. No blind texture resizing or codec substitution.
- Music uses compressed Ogg, with four combat states sharing the same imported
  stream. AudioManager pools 16 SFX voices; MusicManager owns two crossfade players.
  The discarded synthesis was the clear startup CPU/memory issue.
- Mobile renderer, **MSAA 2× (was off)**, high-quality PCF directional shadows,
  per-arena HDRI panorama IBL, four torch omni lights and the HD arena shell
  (triplanar photo-PBR rock/brick/marble/wood/metal + ~90 additional mesh nodes)
  are the likely GPU costs; animated/skinned enemies, translucent rings,
  per-elite lights, boss lights and GPU particles remain. No custom shader files
  were found. No draw-call or GPU-frame-time measurements were available.
- `canvas_items` stretch may render 3D at high native phone resolution; do not assume
  the 1280×720 viewport setting is a fixed 720p 3D budget. Resolution scaling, shadow
  tiers, light limits, MultiMesh conversion and renderer fallback need visual/device
  comparisons before changing defaults. The 60 FPS Android ceiling is the only new
  steady-state rendering-rate policy.
- Export stays ARM64 + Gradle, pinned to the project's Godot toolchain. No new Android
  permissions or backend services. Excluding tests does not justify switching from
  all-resources export: runtime string-based loads still need the complete catalogue.

## Reproduce and finish runtime verification

With the pinned Godot installed on Linux:

```bash
GODOT_BIN=/path/to/godot bash tool/profile_android.sh
GODOT_BIN=/path/to/godot bash tool/profile_android.sh --low-tier
# Optional desktop renderer (requires a display/GPU; still NOT Android):
HEADLESS=0 GODOT_BIN=/path/to/godot bash tool/profile_android.sh

GODOT_BIN=/path/to/godot bash scripts/build_android.sh
```

The profile launcher uses disposable XDG save data, imports once, then launches a
fresh process twice (new save / existing save). It has timeouts and treats engine
errors or a missing completion marker as failures, even if Godot exits zero.

The probe exercises the real autoloads/Main, all three arenas, 12 menu/run/game-over
cycles plus 12 direct restarts, pause/resume, held attack/movement, VFX teardown,
invalid projectile fallback, material reuse and simultaneous text expiration.
Test-only invulnerability keeps short gameplay samples alive. It records world-build
milliseconds, process/physics monitor distributions, frame-interval p50/p95/p99/max,
object/resource/node/orphan counts, signal cleanup and restored FPS policy. Rendering
metrics are marked **-1 / unavailable** when headless. This is an initial-wave,
short-duration lifecycle workload, not a late-wave/boss or thermal soak.

`PERF REPORT:` JSON is written to `build/perf/fresh.log` and `existing.log`. Compare
identical workloads, engine version, renderer, OS and build flags against the baseline.
Import time is separate from installed-app cold startup. Startup `elapsed_msec` is
Godot's clock, not Android launch-to-first-presented-frame timing.

### Required physical-device matrix (pending)

1. Build/install the APK; check manifest, ABI, bundled runtime catalogue and absence
   of test resources. Run existing Godot unit tests and native import validation.
2. Use at least one low-range (2–3 GB RAM) and one mid-range ARM64 device. Record model,
   Android version, GPU/driver, display resolution/refresh rate, build type, and renderer.
3. Fresh-data launch and warm-cache process-cold launch: force-stop between runs;
   collect 10 repetitions. `adb shell am start -W` is activity timing, not proof of the
   first usable game frame; pair it with a trace/first-frame observation.
4. Capture `adb logcat` for script/native errors, AndroidRuntime, low-memory kills and
   ANRs. Sample `adb shell dumpsys meminfo com.laststandarena.game` after menu, first
   run, each arena, and 20+ restarts. Look for a plateau after caches warm, not only a
   smaller first snapshot. Use Perfetto/Godot profiler for stalls and GPU/render work.
5. Play melee/ranged, status stacks, splitter/exploder chains, crowded late waves and
   boss phases. Measure p50/p95/p99 and worst frame, draw calls, CPU/physics/GPU times,
   resource/texture memory, scene-build latency and spawn spikes.
6. Exercise pause/resume, settings, upgrades, game over, direct restart, menu-to-run,
   background/foreground, screen off/on and process recreation with an existing save.
7. Soak 20–30 minutes with stable brightness and thermal conditions, unplugged.
   Compare sustained FPS, temperature/throttling and battery drain. Verify Android
   high/ultra stays capped at 60, low remains 30, and physics stays 60 Hz.

Until those checks pass, treat this patch as **targeted fixes with passing static
regressions**, not a proven stable/performance-qualified Android release.
