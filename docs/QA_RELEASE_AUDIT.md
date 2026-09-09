# QA & Release-Readiness Audit — Last Stand: Arena

**Scope:** final quality pass on the existing game. No new gameplay, no redesign, no
speculative rewrites. Branch `arena/01a08132-game-no-7`, based on `main` @ `3751371`.

**Flow exercised (by reading and simulating, see *Verification* for why):** launch →
autoload boot → main menu → run setup → start run → world build → character spawn →
combat/skills/pickups/waves → pause → resume → main menu → restart → game over → relaunch.

---

## Critical bugs fixed

### 1. Every skill coming off cooldown raised a runtime error
`scripts/ui/skill_bar.gd`

`SkillController` declares `signal skill_became_ready(skill_id: StringName)` — one
argument — and emits it in `_tick_cooldowns` whenever a cooldown reaches zero. `SkillBar`
connected it to `_on_cooldown_event(_skill_id: StringName, _duration: float)`, which
requires **two**. Godot raises *"too few arguments for signal"* on every emission, so the
error fired continuously during normal play, for all three skill slots, in every run.

The `has_signal()` guard around the connect passes, so the bad connection was always made.
`bind_controller()`'s disconnect referenced the same wrong pair, so it never actually
disconnected — rebinding (each new run) leaked the stale connection.

**Fix:** dedicated 1-arg `_on_skill_ready(skill_id)`; connect *and* disconnect updated.

> The pre-existing guard `tests/python/test_regress_ui_skillbar_and_joystick.py` only
> asserted the string `"skill_became_ready"` appears in the file, so it could not detect
> that the callable's arity was wrong.

### 2. Pausing, then quitting to the main menu, froze the next run permanently
`scripts/core/game_root.gd`

```gdscript
func request_main_menu() -> void:
    _paused = false                  # <-- local flag only
    transition_to(State.MAIN_MENU)
```

`_set_paused()` is what owns `get_tree().paused` and `RunState.paused`. Assigning
`_paused` directly left the **SceneTree paused forever**. It then gets worse: `_set_paused`
opens with `if _paused == value: return`, so with `_paused` already `false` every later
unpause became a no-op, including the one on the `PLAYING` transition.

Simulated sequence — play → pause → main menu → start new run — ends in
`state = playing, tree_paused = true`: gameplay frozen, UI still responsive (UIRoot and
GameRoot are `PROCESS_MODE_ALWAYS`), no in-game recovery. `request_restart()` handled this
correctly, which is why the bug only showed on the menu path.

**Fix:** call `_set_paused(false)`.

### 3. Restarting a run silently renamed the whole world, breaking node lookups
`scripts/main/main.gd`

`_clear_world()` called `queue_free()` on the `WorldRoot` children, then `build_world()`
immediately added the replacements. `queue_free()` is **deferred to end-of-frame**, so the
outgoing `Arena` / `Player` / `SpawnManager` nodes still held their names. Godot resolves
the collision by renaming the *new* nodes to `Arena2`, `Player2`, … for the rest of the
frame.

Anything resolving by path hits the dying node or null — `minimap.gd:55` does exactly
`get_tree().current_scene.get_node_or_null("WorldRoot/Arena")`, so the minimap read the
old arena's extents (or none) after every restart.

**Fix:** `remove_child(child)` before `child.queue_free()`, which frees the name immediately.

### 4. CI's GDScript test gate ran zero tests
`tests/run_tests.gd`

The `godot-tests` CI job runs `godot --headless --script res://tests/run_tests.gd` and
gates the Android build on it. That file had been replaced by a temporary diagnostic stub
that called `load()` on five copies of itself, printed whether each compiled, and exited —
**no assertions executed**. The real runner (21 unit suites + combat, attack-combo, enemy
encounter, boss and spawn-manager integration stages) was parked in `tests/diag_full.gd`,
never referenced by CI.

So the entire GDScript test tier — including the suites that would likely have caught bug
#1 — had been reporting green without running.

**Fix:** `tests/diag_full.gd` → `tests/run_tests.gd`; deleted `diag_var1..4.gd` (2244 lines
of near-identical copies, each retaining one integration stage, kept to bisect a compile
error that no longer exists); registered three unit suites that existed on disk but were in
no runner (`test_character_visuals`, `test_content_progression`, `test_presentation_scripts`
— 24 suites now). No test logic altered.

---

## Major bugs fixed

| # | Area | Issue | Fix |
|---|------|-------|-----|
| 5 | `utilities/performance_monitor.gd` | `Engine.max_fps` is **global**, but the monitor is a **per-run** node. A run that auto-degraded to the LOW tier capped the whole app — menus included — at 30 fps for the rest of the session; nothing restored it on teardown. | **Superseded on merge.** `main` fixed this independently while this branch was in review, restoring the cap from `ProjectSettings` in `_exit_tree()`. That is the better mechanism — it cannot capture an already-degraded cap — so this branch's snapshot version was dropped during the merge and `main`'s kept. The regression guard here now pins the *guarantee* (teardown reassigns `Engine.max_fps`) plus a check that only one `_exit_tree` exists, since keeping both would be a duplicate-definition parse error. |
| 6 | `ui/run_setup_panel.gd` | `OptionButton.selected` is `-1` until the user picks (and after any list rebuild). `_arena_ids[_arenas.selected]` / `_weapon_ids[_weapons.selected]` then index **out of bounds** on the arena-select and launch paths. | Clamped accessors `_selected_arena_index()` / `_selected_weapon_index()`. |
| 7 | `ui/ui_root.gd` | `find_child("StatusTitle", …) as Label` is dereferenced unchecked in `_sync_from_state()`, which runs on **every** state change — a null yields a hard crash rather than a missing caption. | Null-check before assigning `.text`. |

---

## Minor issues fixed

- **`ui/damage_number_layer.gd`** — `set_max_live()` clamped to the initial pool size (32),
  so `PerformanceMonitor.max_damage_numbers()`'s ULTRA budget of 48 was **unreachable**; the
  setter silently did nothing above 32. Pool now grows to the requested budget
  (`MAX_POOL = 64`). Also, the pool-exhaustion path in `_obtain()` popped the oldest live
  entry and returned its label **without resetting it**, handing the caller a label still
  carrying the dropped entry's visibility/scale/alpha. Now reset before reuse.
- **`gdlint` failed on the repo** (exit 1, two `function-variable-name` violations:
  `_p_check`, `_pl` — a *used* local must not start with `_`), while `docs/BUILD.md`,
  `docs/PLAYER_IMPLEMENTATION.md` and `docs/AGENT5_UI_HANDOFF.md` all state the lint passes.
  **Superseded on merge:** `main` fixed the same two violations independently, with
  different names (`player_check`, `live_player`). Those conflicted on merge and were
  resolved in `main`'s favour, so this branch's rename commit is now a no-op. `gdlint`
  is clean either way.
- **`docs/ANDROID_PERMISSIONS.md`** claimed the game "does not call
  `vibrate_handheld`/haptics" as evidence for the no-permission posture. It does, in
  `touch_action_button.gd` and `player_feedback.gd` (both gated on the user's
  `vibration_enabled` setting). The conclusion still holds — `VIBRATE` is a *normal*,
  non-prompting permission Godot adds automatically — but the stated evidence was false and
  a privacy review checking it against the code would flag it. Documented accurately.
- **27 regression guards added** (`tests/python/test_regress_qa_release_audit.py`), one per
  fix, including a structural check that every `tests/unit/*.gd` file is registered in the
  runner and that the `diag_*` duplicates stay deleted.

---

## Performance findings

*Observations, not changed — none is a correctness bug, and fixing them means touching
gameplay-adjacent tuning.*

- **`projectile.gd::_apply_team_tint()`** allocates a **new `StandardMaterial3D` per
  projectile launch** when the mesh lacks `set_team_tint`. At high fire rates this is the
  single largest avoidable per-frame allocation. Cache two shared materials (player/enemy).
- **`damage_number_layer._process`** iterates `_live.duplicate()` and `erase`s by dictionary
  identity — O(n²) plus a full array copy every frame. Fine at 32 entries, worth a
  backwards-iterating index loop now that the pool can reach 64.
- **`minimap._refresh_targets()`** (15 Hz) calls `get_nodes_in_group` three times and
  re-resolves the arena by path each tick; the arena reference could be cached per run.
- **`PerformanceMonitor` step-up requires 900 samples (~15 s)** of >57 fps with a 5 s
  cooldown; recovery from a transient dip is slow. Intentional-looking, flagged for tuning.
- **`ProjectilePool`** pre-spawns 48 and recycles oldest-first without ever returning null —
  good. Note `_obtain()`'s `else` branch calls `_make_projectile()`, which does not append to
  `_idle`, making the two following `erase` calls inert (harmless dead work).
- **`wave_manager._apply_director_count_nudge`** appends `queue[i % queue.size()]` while the
  queue grows, so the sampled distribution skews toward early entries. Deterministic, so not
  a bug — but the intent was probably to sample the original queue.
  **RESOLVED (2026-09-09):** the nudge is now a pure static `apply_count_nudge` that spreads
  additions/removals evenly across the ORIGINAL queue (no head bias, no `pop_back` deleting
  late elites/bosses); unit + regression guards added.

---

## Architecture findings

- **Enemy scenes are half-inherited, half-copied.** `basic/fast/heavy_enemy.tscn` inherit
  `enemy_base.tscn` (2 nodes each); `dasher/exploder/ranged/splitter/warlord` are hand-copied
  16–17-node trees differing only by an added `EnemyAnimator`. **Any future edit to
  `enemy_base.tscn` silently misses 5 of the 8 enemies.** This is the highest-value structural
  cleanup left, and the most likely source of a subtle "works for some enemies" bug.
  **RESOLVED (2026-09-08 follow-up):** all 8 archetypes are now true child scenes of
  `enemy_base.tscn` overriding only archetype-specific properties; enforced by
  `tests/python/test_regress_enemy_scene_inheritance.py` + `tests/unit/test_enemy_scene_inheritance.gd`.
- **EventBus subscriptions are never released.** 26 files connect to EventBus signals;
  **zero** disconnect. Per-run nodes are freed on teardown so Godot drops those connections
  automatically — this is not currently a leak — but it is load-bearing on that assumption
  and any future `RefCounted`/autoload subscriber would leak silently.
- **Two sources of truth for best score/wave.** `GameRoot.get_best_score()` /
  `get_best_wave()` (`game_root.gd:74/78`) have **zero callers** — `menu_panel`,
  `run_summary_panel`, `test_harness` and the UI test runner all read `SaveManager` directly.
  Dead facade; either route everything through it or delete it.
  **RESOLVED (2026-09-08 follow-up):** accessors deleted; SaveManager is the single public
  read path, GameRoot's `_best_*` mirrors are internal (run_ended + debug snapshot).
- **Fragile hardcoded path.** `minimap.gd:55` hardcodes `"WorldRoot/Arena"` off
  `get_tree().current_scene`; breaks if the minimap is used outside `main.tscn` or the arena
  node is renamed. (Fix #3 removes the *stale-node* failure mode, not the fragility.)
  **RESOLVED (2026-09-08 follow-up):** the minimap resolves the arena through
  `Arena.ARENA_GROUP` first, with the legacy path kept only as fallback.
- **~187 uncalled private functions**, mostly tail `_validated_*` / `_export_range_guard*`
  helpers under `## Hardened:` comments. Many are *asserted to exist* by
  `tool/validate_guards.py` and the Python suite, so they cannot be removed piecemeal —
  removal must update the validator in the same commit. **Left in place deliberately:**
  deleting them is a large, purely-cosmetic diff that would collide with every in-flight
  branch. Recommended as a dedicated follow-up once branches have landed.
- **`ContentRegistry._ready()`** reports validation errors but never halts or enters the
  ERROR state; `_validation_dirty` is write-only; `validate_all()` calls the expensive
  `refresh_all()` and its duplicate-id loop is unreachable. `get_camera_profile` falls back
  to `&"default"` while `get_enemy`/`get_weapon` return null — inconsistent contracts.
  **RESOLVED (2026-09-09):** `_ready()` now halts in debug/test builds when content
  validation fails; `_validation_dirty` and the unreachable duplicate loop were deleted
  (ContentLoader already rejects duplicates). The `get_camera_profile` default-vs-null
  contract difference is a separate, intentional tolerance (camera has a shipped default
  fallback; other content does not) and is left unchanged.

---

## Remaining known issues

1. **Godot was never executable in this sandbox**, so `--headless --check-only`, project
   import, `tests/run_tests.gd` and `validate_asset_imports.gd` could not be run locally;
   the substitute toolchain is described under *Verification*. This prediction proved
   correct and then some: the first honest CI run surfaced **20 pre-existing failures**,
   all now fixed (see *Phase 2*). **Both the Godot job and the Android build are now green
   on PR #18.**
2. **The Android APK now builds in CI** (2m43s) — it had been skipped for the life of this
   branch because it is gated on the test job. It is still an unsigned `--export-debug`
   build and **has not been installed or run on a physical device**; no one has verified
   touch input, thermals, or frame pacing on real hardware. Config-level review stands: no
   permissions requested, `arm64-v8a` only, `script_export_mode=2`, immersive, landscape,
   `keep_screen_on`. `export_path` differing from CI's `-debug.apk` is **correct** — the
   preset holds the release default and CI passes an explicit debug path.
3. **The encounter suite now depends on a test-side physics integrator.** `_step_enemy`
   advances the body from `velocity * dt` because `move_and_slide()` ignores the caller's
   delta. That is a faithful stand-in for straight-line motion but it does **not** model
   collision response or floor snapping, so these tests cannot catch regressions in
   collision behaviour. Worth revisiting if enemy movement ever gains terrain interaction.
4. **`scripts/audio/audio_config.gd`** references `res://data/audio_config/` in a comment;
   no such directory exists (streams live in `res://data/audio/`). Comment-only, left alone.
   **RESOLVED (2026-09-08 follow-up):** comment corrected — configs live beside the streams.
5. **Enemy scene duplication** (above) — deliberately not restructured: it is a scene-file
   change that would conflict with any branch touching enemies. **RESOLVED (2026-09-08):**
   all five hand-copied archetypes refactored onto `enemy_base.tscn` inheritance with
   verified tree parity; regression guards added on both sides of the toolchain.
6. **Dead `_validated_*` helpers** (above) — deliberately retained, guarded by the validator.
7. **`ContentRegistry` never halts on validation failure** — changing that is a behavioural
   decision about whether bad content should be fatal; flagged, not changed.
   **RESOLVED (2026-09-09):** bad content is now fatal in debug/test builds (startup
   `assert` in `ContentRegistry._ready()`); release builds report every problem and continue
   with the degraded-but-usable tables, matching the "release logs once, debug asserts"
   convention used for required player components.

---

## Recommended merge order

> **Update 2 (current).** `main` has since absorbed PRs #17, #19 and #20, including a
> sibling agent's stress/soak pass. This branch is merged up to date with that `main`
> (`60cd7ac`). Four conflicts, all resolved deliberately: `health_component.gd` and
> `progression_component.gd` were the **same two bugs found independently** by the other
> agent (kept the variant with one fewer redundant emission / lookup, credited theirs in
> the comment); `game_root.gd` was comment-only; for `main._clear_world()` I took **their**
> `child.free()` over mine, because that code rebuilds the world synchronously and must not
> race a deferred deletion. `gdparse` re-run post-merge confirms no duplicate function
> definitions, the known hazard when two branches fix the same bug in the same file.

| Order | Branch | Overlap with this branch | Result |
|-------|--------|--------------------------|--------|
| — | `arena/01a08130-game-no-7` — character integrity, mount math | none | **Already merged** (PR #17) |
| — | `arena/01a08131-game-no-7` — UI/audio polish, stress/soak fixes | resolved | **Already merged** (PRs #19, #20) |
| 1 | **`arena/01a08132-game-no-7`** (this one, PR #18) | merged up to date with `main` | **Ready to merge — CI green** |

Both sibling branches have landed, so the ordering question below is now historical; this
branch is last and carries the merge resolution. The original reasoning is kept for the
record.

**Merge this branch before `...131`.** It is the only one touching the run lifecycle
(`game_root`/`main`), its changes are small and localized, and `...131` is a broad
cosmetic pass — rebasing a 5-line pause fix onto a large UI diff is far easier than the
reverse.

`...131` overlaps on `game_root.gd`, `main.gd`, `run_setup_panel.gd`, `skill_bar.gd`,
`ui_root.gd`, but touches **disjoint regions**: it does not modify `request_main_menu`,
`_set_paused`, `_clear_world`, the `.selected` indexing, or the skill-bar signal wiring — it
changes layout, touch-target sizing and theming. I confirmed the merged tree keeps all four
critical fixes intact (`_on_skill_ready` wiring, `_set_paused(false)`, detach-before-free).

**Two things to watch when `...131` lands:**
- It restyles `skill_bar.gd` heavily. Whoever resolves must keep `_on_skill_ready` connected
  to `skill_became_ready` — reintroducing `_on_cooldown_event` there restores bug #1.
- It changes `fit_touch_targets(view_width: float)` to `fit_touch_targets(bar_size: Vector2)`.
  Any caller merged from elsewhere must be updated; a stale float call would be a hard error.

`...130` is fully disjoint and can land at any point.

---

## Phase 2 — bugs found by the restored CI gate

Fix `7ceb04a` above restored the real headless test runner (it had been reduced to a
compile probe, so **the Godot job had not actually executed a single assertion**). The
first honest run surfaced 20 failures across five rounds. All of them predated this
branch. Each was classified as a product bug or a stale test by reading the assertion,
reading the implementation, and reproducing the reported numbers before changing anything.

### Product bugs (shipping defects)

| # | Bug | Impact |
|---|---|---|
| P1 | `ProgressionComponent._accumulate` dropped the **first stack of every upgrade** | The finite-guard read `_modifiers.get(k, 0.0)` but the assignment indexed `_modifiers[k]`, which on a missing key errors and yields `null` → `float(null) == 0.0`. `apply_upgrade()` still returned `true`, so it was silent. Every upgrade needed two copies to do anything. |
| P2 | `WavePlanner._counts_for_wave` left the `heavy` tier uncapped | `planned_count()` reached 46 by wave 40 against the file's own documented ceiling of 40. Capped at 12: curve untouched until wave 27, worst case pinned to exactly 40. |
| P3 | `CriticalSystem.roll` let pity manufacture crits from nothing | The pity bonus was added unconditionally, so a weapon at **0% crit still crit** once enough non-crits stacked. Pity now escalates an existing chance only. |
| P4 | `SaveSchema._string_list` corrupted or erased id lists | Built ids with `String(item)` on every element. Values that coerce silently smuggled a bogus id (`4` → `"4"`); values that raise aborted the typed function so the **entire list returned empty** — one malformed entry wiped every equipped weapon. |
| P5 | `BossController._advance_to` lost the phase signal to a cosmetic failure | `_apply_phase_visuals` calls `create_tween()`, which fails outside the tree, aborting between the stat bumps and `phase_advanced.emit()`. Multipliers applied, but UI/audio/analytics never heard about it. |
| P6 | **`HealthComponent.reset()` enraged every boss at spawn** | `reset()` went through `set_max_health()`, which clamps the OLD `current_health` against the NEW maximum and emits that pairing first: resetting a fresh 100 hp component to a 600 hp boss published `health_changed(100, 600)` — a 16% health fraction. `BossController` advances phases one-way, so it read that as past the 33% Enrage threshold and jumped straight to the final phase **before the fight started**: Enrage damage and speed multipliers applied, no Fury phase, no phase signals. |

P6 is the most consequential find of the whole audit: it changed every boss encounter in
the shipped game, and it was invisible because the phase multipliers applied correctly —
only the *timing* was wrong.

### Test-infrastructure defects

These were not product bugs, but they made the suite assert against meaningless data:

- **Node3D fixtures were never in the tree.** `get_global_transform()` falls back to the
  identity transform outside the tree, so parentless dummies all reported
  `global_position == ORIGIN` regardless of the `.position` set on them. `AreaDamage` and
  `MeleeResolver` read `.global_position`, so every target collapsed onto the blast centre:
  radial damage hit an out-of-radius dummy for full damage and melee arc filtering returned
  all four candidates. Fixed by attaching fixtures and splitting the runner's suite list into
  `UNIT_SUITES` (pure) and `NODE_SUITES` (deferred to a live frame).
- **`move_and_slide()` ignores the caller's delta.** Encounter tests drive
  `_physics_process` manually with `set_physics_process(false)` and no real physics frames,
  so bodies never moved and distance-closing assertions watched a stationary enemy.
- **Fixed frame budgets ignored the `hurt` stagger** that `apply_damage` forces before an
  enemy can act, and over-stepped past transitions into a second swing. Replaced with a
  predicate-driven `_step_enemy_until()`.
- **`PackedScene.pack()` only serializes children whose `owner` is the pack root.** The
  spawn-manager fixture never set owners, so spawned enemies had no `HealthComponent`,
  `apply_damage` was rejected, nothing could die, and every defeat/clear assertion failed.
- **`CombatLog.new(4)`** vs the class's `maxi(capacity, 8)` floor, and a melee arc fixture
  sitting at *exactly* the 45° boundary (inclusion decided by float rounding).

### Two process findings worth keeping

1. **GitHub caps `::error` annotations at 10 per step.** The runner emitted one per failure,
   so every round showed exactly 10 and silently dropped the tail — which is why each fix
   appeared to "reveal" a fresh batch. The runner now emits one aggregated annotation. This
   is what exposed the last hidden failure.
2. **String-pinning guards can enshrine bugs.** Two Python guards asserted the literal
   defective expression `"clampf(float(_modifiers"`, so they actively resisted the P1 fix; a
   third pinned `child.queue_free()` and failed the merge when `main` landed an equally valid
   `child.free()`. All three were rewritten to assert the *property* rather than the text.

---

## Verification

**Tooling constraint.** No Godot binary is reachable from this environment: every release
host (github release-assets, objects/raw.githubusercontent, tuxfamily, jsdelivr, several
mirrors, docker, huggingface) fails at TLS; npm and PyPI are the only reachable registries
and neither ships a Linux engine build. `java` and the Android SDK are also absent. I
substituted a static toolchain rather than skipping verification.

**All green on the final commit (tree clean). CI on PR #18 is green end to end: `Validate resources & Python tests` pass, `Godot headless tests` pass, `Build Android APK` pass (2m43s) — the Android build had been gated behind the failing test job and had never run on this branch until now.**

| Check | Result |
|---|---|
| `gdparse` (all `.gd` under `scripts/` + `tests/`) | parses cleanly |
| `gdlint scripts/ tests/` | **Success: no problems found** (was: 2 errors) |
| `tool/validate_resources.py` | Validated 110 files: OK |
| `tool/validate_assets.py` | 81 models, 79 PNGs, 31 audio, 2 fonts — all deps present |
| `tool/validate_guards.py` | 139/139 files, 69 passed, 0 failed |
| `python3 -m unittest discover -s tests/python` | **597 tests OK** (502 at branch point) |

Additionally written for this audit: a signal-arity cross-checker (EventBus, same-file and
cross-class typed vars — found bug #1), a scene-node-path cross-checker (6 hits, all verified
false positives), an EventBus connect/disconnect audit, a group producer/consumer inventory,
and a Python simulation of the `GameRoot` pause/transition state machine (confirmed bug #2
and verified `request_restart()` as a working control).

**Commits** (each self-contained, fixes separated from unrelated changes):

```
ac5ee43  fix: three crash/soft-lock bugs in the core run lifecycle
7ceb04a  ci: restore the real headless test runner (run_tests.gd was a compile probe)
0e617bf  fix: UI robustness and per-run global state leaks
4cfd045  style: fix the two gdlint failures (docs claim the lint is clean)
7ad37b0  docs: correct the Android permission policy on haptics
0db1c65  test: regression guards for the release-readiness QA pass
```

**Phase 2 commits** (CI-gate fixes, likewise separated):

```
3dfcde9  fix: upgrades' first stack silently did nothing; cap wave heavy count
d67d4a5  fix: zero-chance crits, and run Node3D suites inside the live tree
210bbaa  fix: malformed save ids wiped equipped lists; unhide CI failures past 10
faa0aee  test: make encounter stepping physical and condition-driven
1b54d47  fix: boss phase signal lost to a cosmetic failure; unpacked test fixture
73fe82e  test: stop dasher stepping at the recovery release; instrument boss phase
b4962f8  test: report boss health_changed connection count and starting phase
df61895  fix: every boss spawned already enraged (HealthComponent.reset)
60cd7ac  Merge origin/main into arena/01a08132-game-no-7
ffb3008  test: assert detach-before-release as a property, not a literal call
```

**Merge note.** `main` advanced during this phase (PRs #17, #19, #20). Another agent
independently found and fixed P1 and P6; the conflicts were resolved keeping the variant
with one fewer redundant signal emission and crediting the other in the comment. For
`main._clear_world()` I took *their* `child.free()` over my `queue_free()`, because the
surrounding code rebuilds the world synchronously in the same call and must not race a
deferred deletion. Post-merge `gdparse` confirms no duplicate function definitions — the
known hazard when two branches fix the same bug in the same file.
