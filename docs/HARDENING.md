> **STATUS: SUPERSEDED — the `_validated_*` layer described below was removed
> by the typed-architecture refactor** (see docs/REFACTOR_PLAN.md). Measured, not
> guessed: 168 of these helpers were defined and only 27 were ever called — 141
> were dead code ("validation theater") that this doc nonetheless counted as
> coverage. The guards that were *real* were inlined at their use sites and are
> pinned by `tool/validate_guards.py` (real-guard contract) and
> `tool/check_typed_arch.py` (bans `.call("...")`/`has_method` duck typing and
> verifies typed references resolve). The historical list below is kept for
> context only — `func _validated_*` no longer exists anywhere in scripts/.

# Hardening — 4000-line Bug Hunt

This document describes the systematic hardening applied across the 4000-line
sweep (Batch 1–12 + follow-on). Every file listed has a `_validated_*`
helper that clamps, null-guards, or finite-checks its inputs. Regression
tests in `tests/python/test_regress_*.py` assert the helpers exist.

## Why

Godot 4.x is tolerant, but headless tests, reparenting, and JSON round-trips
expose NaN, null, and Dictionary-vs-Object mismatches. The hardening makes
every system tolerant: no crash on bad seed, no freeze on NaN time_scale,
no soft-lock on missing content.

## Coverage — 139/139 GDScripts hardened

- **combat/** — area_damage radial args, hitstop time_scale restore, payload
  deep duplicate, result final clamp, critical finite+RNG guard, query radius
  clamp, log entry validation
- **arena/** — half clamp, config clamp, decorator seed, hazards damage clamp, and the
  authored world: a theme's colour channels and a landmark's footprint are finite-checked at
  load, a non-finite nav blocker is skipped rather than blocking a row, and a landmark kind
  with no builder builds nothing (it no longer defaults to an obelisk)
- **audio/** — volume clamp, fade clamp, cue validation, procedural pitch clamp,
  asset integrator cue/stream guard
- **core/** — run_state currency/score clamp, restore dict filter, content
  registry archetype guard, event_bus safe emit, scene_router id guard,
  content_loader path guard, upgrade_service pool guard, game_root seed guard,
  run_analytics window clamp, run_scorekeeper delta clamp, test_harness seed
- **enemies/** — base is_instance_valid + knockback clamp, config stats clamp,
  state machine id guard, chase/attack/hurt/idle/ranged/dash/fuse/dead validators,
  boss threshold clamp + empty phases guard, elite mult clamp, spawn patterns
  count clamp, animator speed clamp, locomotion integration, navigator target,
  striker execution, ledger archetype, manager configure, placer half
- **main/** — _safe_run/_safe_seed/_safe_arena_id Dictionary branches,
  wave number clamp, delta clamp
- **meta/** — spend guard, unlock guard, and the run-definition resolvers: `GameMode`,
  `Prestige` and `Narrator` null-guard the registry, clamp an unknown mode id or prestige rank
  against what the content actually defines (`clamp_rank`, `validated()`) instead of substituting a
  default, and every authored record is checked by `validate()` at load — a mode that spawns nothing
  and says nothing, a ladder whose titles do not cover `max_rank`, and a cosmetic id `Cosmetics`
  does not know are all startup errors, not runtime surprises.
- **player/** — stamina config clamp, health payload finite, progression stat
  finite (multiplicative floored 0.1 so no zero/negative stall, max_health ≥1), experience xp_mult clamp, locomotion speed, targeting range, attack
  damage, dodge window, animation speed, build id, equipment slot, feedback
  intensity, character_controller input (legacy AttackController isolated, single authority), combo window, health heal amount
- **progression/** — upgrade weight clamp, pick count clamp
- **pickups/** — pickup value clamp, manager pool clamp + drop pos, drop table
  chance clamp, config value/lifetime clamp
- **save/** — currency clamp, save dict filter, schema version, settings
  volume/sensitivity
- **status/** — manager effects filter + finite delta + a typed effect table
  (the per-tick `is_instance_valid(fx)` walk is replaced by `Dictionary[StringName,
  StatusEffect]`, which the manager owns exclusively),
  effect duration clamp, config duration/tick clamp, permanent stun/root/shield rejected, stun/root capped 3s even with 10× duration multiplier, tick hitch guard 64 ticks + 60 cap, move/damage pow NaN→1.0 0..10, DOT/HOT 0..10000
- **skills/** — controller cooldown, config stats, executor cast pos, instance
  cast pos
- **ui/** — minimap pos clamp, upgrade card index, boss fraction, hud fraction,
  skill cd, run summary duration/score, tutorial step + timer finite,
  announcement text, damage label, menu id, run setup seed, safe area inset,
  touch action/cooldown, joystick vec, settings slider, ui root state, gallery
  index, armory cost, help id, backdrop alpha, achievement gallery
- **utilities/** — rng salt/chance/range guards, weighted total clamp + weight
  finite, pool size/instance, remapper action/event, json dict/path,
  performance sample, input remapper
- **visuals/** — effect scale, ring fade time, model path, character model id,
  mount host, decorator, hazards, procedural, mount
- **waves/** — planner archetype count, manager wave number, director prune
  finite + factor clamp, config counts, mutators weight, scoring delta/wave,
  spawn entry archetype/count, scoring
- **weapons/** — projectile active+delta finite + launch dict, pool projectile
  + capacity, instance config/level, manager pool + weapon id, melee/ranged
  resolvers + config stats, config damage/cooldown/range

## Invariants enforced

1. **No bare GameRoot.get_run().seed** — always via `_safe_seed()` or Dictionary
   branch (`is Dictionary` + `"key" in run`).
2. **No bare ContentRegistry.get_* without null** — check `ContentRegistry == null` and take
   the content-folder fallback. Duck-typing the registry (`has_method("get_*")`) is banned by
   `tool/validate_guards.py`: a method that may or may not exist is a seam, and seams do not fail
   loudly.
3. **No bare EventBus.emit without is_instance_valid** — pooled feedback checks
   `is_instance_valid`.
4. **All floats entering physics are finite** — `is_finite` + `clampf` before use.
5. **All pool sizes clamped** — `clampi(pool_size,1,N)` to prevent OOM.
6. **All time_scale writes restored on _exit_tree** — hitstop_manager.

## Regression tests

- `test_regress_batch12_guards` — Dictionary branches

Every name below is a file that exists: the four suites this doc used to list
(`test_regress_enemy_hardening`, `test_regress_combat_hardening`, `test_regress_ui_visuals_audio`,
`test_regress_export_ranges_and_scoring`) were folded into the sweeps years ago and stopped being
files, which is the same failure mode as a doc describing a table nobody reads.

- `test_regress_player_hardening` — player finite
- `test_regress_wave_systems` — wave planner/manager
- `test_regress_core_utilities` — run_state/rng/weighted
- `test_regress_remaining_risks` — exhaustive sweep
- `test_regress_tooling_and_ci` — CI split pipeline
- `test_regress_arena_world_data` — the arena's theme/landmark/obstacle data, the death of the
  id-keyed tables and Dictionary records, and every shipped look number audited against the
  values the deleted tables held
- `test_regress_wave_mutators` — mutator data, the folded `WaveModifiers` record, the fold order
- `test_regress_run_modes` — the seven authored modes, the prestige ladder, the announcer's
  provenance, and the ban on Dictionary records or id-matching anywhere in the run-definition layer


## CI split (was monolith)

`.github/workflows/android.yml` now has 4 jobs:

- `validate-resources` (fast, no Godot): validate_resources, verify assets,
  validate_assets, unittest
- `godot-tests` (needs import): setup-godot, import, run_tests.gd,
  validate_asset_imports.gd
- `build-android` (needs both): JDK17, Android SDK, import, build template,
  export APK, verify, upload
- `publish-release` (needs build, on tag/workflow_dispatch): download, unzip
  -t, sha256sum, gh-release

Each stage uploads its own `reports-*` artifact so failures bisect trivially.

## Tooling

- `tool/validate_resources.py` — load_steps + ext_resource existence
- `tool/validate_assets.py` — GLB/PNG/OGG integrity, checksum lock, deps
- `tool/validate_guards.py` — pins the real inlined guards (post-refactor contract)
  (175 checks as of the run-definition pass, up from 99: every authored mode, ladder rule and
  deleted code table is pinned there too)
- `tool/check_typed_arch.py` — typed-architecture gate (no duck typing; refs resolve)
- `tool/check_engine_api.py` — engine-API contract gate: every typed member access, bare global
  call and `.tscn`/`.tres` property is checked against `tool/godot_api_manifest.json` — the
  pinned engine's own ClassDB (4.4.1-stable, reduced from the official source tag by
  `tool/build_api_manifest.py`, so the gate is hermetic). Severity follows the engine's own
  analyzer: unknown members on hard-typed builtin receivers and unknown scene/resource properties
  fail the build (that is the class of bug that shipped five times — `AABB.has_area()`,
  `fposmodf`, `get_surface_material_override_count`, `path_height_tolerance`,
  `PanoramaSkyMaterial.energy` — and twice more in this tree before the gate existed:
  `AudioStreamRandomizer.randomization_type` in all nine `data/audio/*.tres`, and
  `Environment.background_sky` in `arena.tscn` + `arena.gd`); unknown members on Object-derived
  receivers are reported as `[unsafe]` warnings, matching the engine's UNSAFE_PROPERTY_ACCESS
- `tool/check_scene_paths.py` — scene-path contract gate: the game's own tree contract, the
  sibling of the engine-API gate. Every string-literal `get_node`/`get_node_or_null` in
  `scripts/` and `tests/` is resolved against the actual `.tscn` node hierarchies plus
  runtime `.name = "..."` assignments and autoloads; scene-authored `NodePath(...)` properties
  are resolved relative to the node carrying them; every `[node parent="..."]` is verified
  instance-aware (the enemy-variant pattern instances `enemy_base.tscn` and overrides nodes
  inside its subtree); `get_node("P") as T` is checked against the declared node class via the
  ClassDB inheritance in `tool/godot_api_manifest.json`. A renamed/removed node is a runtime
  error per the pinned engine's own `Node.get_node` docs, and no syntax gate can see it —
  its first run found one already: `projectile.gd` looked up a `"Trail"` child that exists in
  no scene and no code, wrote it to a member nothing ever read, and had done so on every
  headless run without a peep
- `scripts/download_assets.py --verify` — offline checksum lock verification

## How to add a new system

1. Put the numbers in a `@export_range` on a `ValidatedConfig` subclass, and say what is wrong
   in `validate()`. Bounds in a `_validated_*`-style wrapper are the theater this file used to
   recommend: they re-ran on every call, they could not see a missing field, and
   `tool/validate_guards.py` now fails the build if one comes back ("no
   `_validated_`/`_guarded_`/`_safe_emit` functions"). Load-time validation reports the whole
   list once, in the right order of severity.
2. A field must have a reader. When a value crosses a boundary, cross it as a typed field on a
   record (`WaveModifiers`, `DamagePayload`) rather than a Dictionary key: a key nobody reads is
   invisible, and `tests/python/test_regress_wave_mutators.py` is the shape of the gate that
   catches it (one `READERS` table, one assertion per field).
3. Run `python3 -m unittest discover -s tests/python -v` and
   `python3 tool/validate_guards.py` — both must be green before push.
4. Run `python3 tool/validate_resources.py && python3 tool/validate_assets.py &&
   python3 tool/check_typed_arch.py && python3 tool/check_engine_api.py &&
   python3 tool/check_scene_paths.py`.

## Metrics

The coverage count above is the sweep's own, frozen: it says how many files that pass touched, and
rewriting it would rewrite history. These are current, and
`tests/python/test_regress_run_modes.py::DocCountTests` re-derives the GDScript count, the validated
file count and the guard-needle count from the tools themselves rather than trusting this prose:

- Start: 1901 sum (1719 ins / 182 del)
- After sweep: 4000+ sum (target 4000)
- Tests: 770 python + the headless Godot suites (was 95) — all green. The two branches merged in
  `main` brought their own suites (`test_regress_systems_completion`, `test_regress_solid_props_and
  _buttons`, the camera-containment and minimap sweeps), which is most of that growth; the run-
  definition pass added `test_regress_run_modes`.
- GDScripts under `scripts/`: 192 (was 139 at the sweep; the subsystem rebuilds since have added
  their config/record types, each of which is `validate()`-checked at load rather than guarded per
  call)
- Validated files: 159/159 (was 85, then 151: +7 authored game modes, +1 prestige ladder)
- Guard needles: 195 (was 61, then 99, then 175 at the run-definition pass) — each one an inlined
  guard, a bounded export, or an absence; the merge of `main` and the four headless rounds that
  followed added nineteen, of which one refuses
  an engine member that does not exist (`.has_area()` on an `AABB`, a parse error that took two
  passes to surface because another parse error was masking it)
  and two pin the sweeps that closed the fifth round: no resource built with `.new()` inside a
  function may go unattached, and no function declaring a return type may be written without a
  `return`
  (the wave-mutator pass added 38, the run-definition pass 76, most of both saying "this Dictionary
  shape must not come back")
