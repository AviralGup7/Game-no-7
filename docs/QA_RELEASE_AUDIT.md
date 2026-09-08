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

---

## Architecture findings

- **Enemy scenes are half-inherited, half-copied.** `basic/fast/heavy_enemy.tscn` inherit
  `enemy_base.tscn` (2 nodes each); `dasher/exploder/ranged/splitter/warlord` are hand-copied
  16–17-node trees differing only by an added `EnemyAnimator`. **Any future edit to
  `enemy_base.tscn` silently misses 5 of the 8 enemies.** This is the highest-value structural
  cleanup left, and the most likely source of a subtle "works for some enemies" bug.
- **EventBus subscriptions are never released.** 26 files connect to EventBus signals;
  **zero** disconnect. Per-run nodes are freed on teardown so Godot drops those connections
  automatically — this is not currently a leak — but it is load-bearing on that assumption
  and any future `RefCounted`/autoload subscriber would leak silently.
- **Two sources of truth for best score/wave.** `GameRoot.get_best_score()` /
  `get_best_wave()` (`game_root.gd:74/78`) have **zero callers** — `menu_panel`,
  `run_summary_panel`, `test_harness` and the UI test runner all read `SaveManager` directly.
  Dead facade; either route everything through it or delete it.
- **Fragile hardcoded path.** `minimap.gd:55` hardcodes `"WorldRoot/Arena"` off
  `get_tree().current_scene`; breaks if the minimap is used outside `main.tscn` or the arena
  node is renamed. (Fix #3 removes the *stale-node* failure mode, not the fragility.)
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

---

## Remaining known issues

1. **Not executed: Godot itself.** No engine binary could be obtained in this sandbox
   (see *Verification*), so `--headless --check-only`, project import, `tests/run_tests.gd`
   and `validate_asset_imports.gd` were **not run here**. Fix #4 means CI will now genuinely
   execute the GDScript suite — **expect the first run on this branch to be the first honest
   result in a while, and budget for it surfacing pre-existing failures.**
2. **Not executed: the Android build.** No JDK and no Android SDK in the sandbox, so the
   Gradle export could not run locally. Android review was config-level: the preset requests
   no permissions, targets `arm64-v8a` only, `script_export_mode=2`, immersive mode,
   landscape-locked, `keep_screen_on`. `export_path` (`build/LastStandArena.apk`) differing
   from CI's `-debug.apk` is **correct** — the preset holds the release default and CI passes
   an explicit debug path.
3. **`scripts/audio/audio_config.gd`** references `res://data/audio_config/` in a comment;
   no such directory exists (streams live in `res://data/audio/`). Comment-only, left alone.
4. **Enemy scene duplication** (above) — deliberately not restructured: it is a scene-file
   change that would conflict with any branch touching enemies.
5. **Dead `_validated_*` helpers** (above) — deliberately retained, guarded by the validator.
6. **`ContentRegistry` never halts on validation failure** — changing that is a behavioural
   decision about whether bad content should be fatal; flagged, not changed.

---

## Recommended merge order

> **Update.** Since this section was first written, `arena/01a08130-game-no-7` has been
> merged to `main` (PR #17), along with an Android performance pass. This branch has been
> merged **up to date with the new `main`** — three conflicts (`tutorial_manager.gd`,
> `wave_manager.gd`, `test_regress_sweep_fixes.py`) were all resolved in `main`'s favour,
> plus a duplicate `_exit_tree` in `performance_monitor.gd` removed. See the two
> *Superseded on merge* notes above. Full gate re-run green on the merged tree.

| Order | Branch | Overlap with this branch | Result |
|-------|--------|--------------------------|--------|
| — | `arena/01a08130-game-no-7` — character integrity, mount math | none | **Already merged** (PR #17) |
| 1 | **`arena/01a08132-game-no-7`** (this one) | merged up to date with `main` | Merge next |
| 2 | `arena/01a08131-game-no-7` — UI/audio polish | 5 files | Clean, auto-merges |

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

## Verification

**Tooling constraint.** No Godot binary is reachable from this environment: every release
host (github release-assets, objects/raw.githubusercontent, tuxfamily, jsdelivr, several
mirrors, docker, huggingface) fails at TLS; npm and PyPI are the only reachable registries
and neither ships a Linux engine build. `java` and the Android SDK are also absent. I
substituted a static toolchain rather than skipping verification.

**All green on the final commit (tree clean):**

| Check | Result |
|---|---|
| `gdparse` (all `.gd` under `scripts/` + `tests/`) | parses cleanly |
| `gdlint scripts/ tests/` | **Success: no problems found** (was: 2 errors) |
| `tool/validate_resources.py` | Validated 110 files: OK |
| `tool/validate_assets.py` | 81 models, 79 PNGs, 31 audio, 2 fonts — all deps present |
| `tool/validate_guards.py` | 139/139 files, 69 passed, 0 failed |
| `python3 -m unittest discover -s tests/python` | **529 tests OK** (502 before, +27 new) |

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
