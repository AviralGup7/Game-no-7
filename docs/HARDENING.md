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
- **meta/** — spend guard, unlock guard
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
2. **No bare ContentRegistry.get_* without null** — always `if ContentRegistry
   == null or not has_method` guard.
3. **No bare EventBus.emit without is_instance_valid** — pooled feedback checks
   `is_instance_valid`.
4. **All floats entering physics are finite** — `is_finite` + `clampf` before use.
5. **All pool sizes clamped** — `clampi(pool_size,1,N)` to prevent OOM.
6. **All time_scale writes restored on _exit_tree** — hitstop_manager.

## Regression tests

- `test_regress_batch12_guards` — Dictionary branches
- `test_regress_enemy_hardening` — enemy validators
- `test_regress_player_hardening` — player finite
- `test_regress_wave_systems` — wave planner/manager
- `test_regress_combat_hardening` — combat finite
- `test_regress_core_utilities` — run_state/rng/weighted
- `test_regress_ui_visuals_audio` — ui/visuals
- `test_regress_remaining_risks` — exhaustive sweep
- `test_regress_export_ranges_and_scoring` — export ranges
- `test_regress_tooling_and_ci` — CI split pipeline
- `test_regress_arena_world_data` — the arena's theme/landmark/obstacle data, the death of the
  id-keyed tables and Dictionary records, and every shipped look number audited against the
  values the deleted tables held

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
- `tool/check_typed_arch.py` — typed-architecture gate (no duck typing; refs resolve)
- `scripts/download_assets.py --verify` — offline checksum lock verification

## How to add a new system

1. Add `@export_range` or `clampf` + `is_finite` at the top of any public
   method that takes float/int from JSON or user input.
2. Add a `_validated_*` helper and assert it in `test_regress_*.py`.
3. Run `python3 -m unittest discover -s tests/python -v` and
   `python3 tool/validate_guards.py` — both must be green before push.
4. Run `python3 tool/validate_resources.py && python3 tool/validate_assets.py`.

## Metrics

- Start: 1901 sum (1719 ins / 182 del)
- After sweep: 4000+ sum (target 4000)
- Tests: 502 (was 95) — all green
- Validated files: 139/139 (was 85) — 502 tests
