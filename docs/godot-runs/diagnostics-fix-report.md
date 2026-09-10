# Godot 4.7.2 diagnostics — remediation report

Branch `arena/01a08a34-game-no-7`. Baseline harvest:
`docs/godot-runs/diagnostics-4.7.2-lsp.txt` — **172 warnings, 0 errors**, 13 categories,
collected from Godot 4.7.2.stable's built-in language server (`tool/lsp_diagnostics.py`,
which `didOpen`s every `.gd` in the project and reads `publishDiagnostics`).

> **Verification caveat.** The Godot 4.7.2 binary cannot be obtained in this sandbox (all
> godotengine/GitHub release hosts fail TLS), so the analyzer can only be re-run through CI.
> The GitHub token in this session expired (`gh auth status` → *"The github.com token in
> GH_TOKEN is no longer valid"*; both `GH_TOKEN` and `GITHUB_TOKEN` return *Bad credentials*),
> so the last two commits could not be pushed and **the post-fix diagnostic count is not yet
> measured**. Everything marked ✅ below was executed and observed in this session; the
> analyzer re-run is marked ⛔ and is blocked on the push.

---

## 1. Parse errors

**3 reported → 1 root cause → fixed and CI-verified** (this was verified earlier in the
session, before the token expired).

| File | Root cause | Fix |
|---|---|---|
| `scripts/ui/virtual_joystick.gd:1` | `class_name VirtualJoystick` — Godot 4.7 added a **native** class of that name; `Class "VirtualJoystick" hides a native class` is a hard parse error | Renamed the script class to `class_name TouchJoystick`. Header docstring records why it must not be renamed back |
| `scripts/main/main.gd:0` | Not its own error — it instantiates `TouchControls`, which preloads `virtual_joystick.gd`; the failure cascaded | No edit needed; cleared by the rename |
| `tests/unit/test_locomotion_nan.gd:47` | Same cascade via `touch_controls.gd` | **Repaired, not deleted or disabled** — no edit needed to the test itself once the class resolved |

The rename touched only the class name and its references (`touch_controls.gd`,
`ui_root.gd`, `main.gd`, the test). No stubs, no commenting-out, no test removal.

CI result after that fix: **`GDScript tests: 1095 total, 0 failed`** (baseline was
`1055 total, 1 failed`), 0 `SCRIPT ERROR`, clean editor log.

---

## 2. Warning categories fixed — 129 of 172

| Category | N | What was done |
|---|---|---|
| `SHADOWED_GLOBAL_IDENTIFIER` | 27 | Semantically justified renames, every reference updated: `seed`→`run_seed` (19 params + the `RunState` field), `range`→`attack_range`, `floor`→`floor_hit`/`lifted`, `exp`→`xp`, `log`→`combat_log`, `chance`→`probability`, `capacity`→`initial_capacity`, `tag`→`pool_tag`, `world_xz`→`world_offset`, `cue_id`/`hazard_id`→`id`, `mount`→`mount_point`, `basis`→`target_basis` |
| `UNUSED_PARAMETER` | 21 | Each signature read first; the 21 genuinely-unintentional parameters were underscore-prefixed (`_cfg`, `_archetype`, `_weapon_id`, `_tree`, …). Lambda params `a0..a3`→`_a0.._a3`. **No parameter was dropped** — signatures are unchanged for callers |
| `SHADOWED_VARIABLE_BASE_CLASS` | 19 | Semantic renames away from the engine member they hid: `name`→`bus_name`/`step_name`/`name_label`/`case_name`, `text`→`message`, `size`→`font_size`, `position`→`pointer_position`, `owner`→`actor`/`body`/`source` |
| `INTEGER_DIVISION` | 19 | **All 19 read individually; all 19 genuinely want whole units, so none became float arithmetic.** GDScript has no `//` operator (the operator reference lists `*`, `/`, `%` only), so truncation is written as `int(a / float(b))` — `int()` truncates toward zero exactly like int/int, bit-identical for every sign |
| `REDUNDANT_AWAIT` | 15 | Every one was `await` on a function that itself contains no `await`, so nothing suspended. Each target body was checked for a coroutine before the keyword was dropped: `_mount_checks`, `_verify_lifecycle` (12 sites), `_test_armory_and_save` |
| `SHADOWED_VARIABLE` | 11 | Renamed the inner binding only, so the outer value is still what the surrounding code reads: `_target`→`_hit_target`, etc. |
| `INT_AS_ENUM_WITHOUT_CAST` | 5 | The engine names its own fix — cast with `as`. Same integers, now typed: `code as Key`, `code as JoyButton`, `level as Viewport.MSAA` |
| `CONFUSABLE_LOCAL_DECLARATION` | 4 | Only the inner name changed: A* flat index `i`→`cell_i`, look-around `angle`→`look_angle`, early-exit `bus`→`warn_bus` (×2) |
| `UNUSED_VARIABLE` | 3 | `minimap.gd`, `ui_theme.gd` locals removed; `stress_loops_inner.gd` `g0` underscored |
| `INCOMPATIBLE_TERNARY` | 3 | Both branches now share a type: `CRIT_SCALE` is a float so the crit branch was float against an int `22`; the jitter x was int `0` against a float `randf_range`; `effect_id` is a `StringName` against a `String` |
| `UNUSED_PRIVATE_CLASS_VARIABLE` | 1 | `effect_director.gd`'s `_bus` was the only one of four `EventBindings` members that never called `bind()` or `unbind_all()` — it wires through `EventBus.bind(self, …)` instead. Dead field removed; the other three untouched |
| `UNREACHABLE_CODE` | 1 | `upgrade_panel.gd:135` — dead code after `return`, removed |

### Two things found while fixing, worth flagging separately

**`test_wave_planner_int_division` was a fiction test.** It asserted that the GDScript source
of `wave_planner.gd` contains `extra // 2` — an operator GDScript does not have. It passed
only because a *comment* contained that text. The comment now states the real rule and the
test pins the real expressions.

**`WeaponConfig.range` was an `@export var`.** Renaming it to `attack_range` silently breaks
`.tres` deserialization, so all 9 `data/weapons/*.tres` were updated in the same commit
(`ab13286`). Worth knowing for any future export rename.

---

## 3. Warnings intentionally retained — 43 `UNUSED_SIGNAL`

41 in `scripts/core/event_bus.gd`, 2 in `scripts/enemies/enemy_base.gd`
(`state_changed`, `attack_started`).

**Exact warning:** `The signal "…" is declared but never explicitly used in the class.`

**Why it fires:** the check is *local to the declaring script*. `EventBus` is an autoload;
every emitter lives in another file and calls `EventBus.<signal>.emit(…)`. The analyzer never
looks across files, so it flags **every** signal declared in `event_bus.gd` — all 41 of them —
regardless of whether they are used.

**Evidence, all 43 audited project-wide** (`scripts/` + `tests/`, `.emit(` and
`emit_signal("…")` for emitters, `.connect(` / `EventBus.<name>` for listeners):

```
signal                       emit  listeners      signal                       emit  listeners
game_state_changed             1     6            status_applied                 1     2
run_started                    1    14            status_expired                 1     0
run_ended                      1     9            player_leveled_up              1     3
player_health_changed          2     2            stamina_changed                2     1
player_died                    1     5            boss_phase_changed             1     4
enemy_spawned                  1     4            boss_spawned                   2    10
enemy_damaged                  1     7            boss_slain                     1    10
enemy_killed                   2    15            wave_mutator_applied           1     0
wave_started                   2    12            achievement_unlocked           1     3
wave_progressed                2     1            tutorial_step_completed        1     0
wave_completed                 1    12            announcement                   8     3
upgrade_choices_presented      1     1            objective_progress             1     3
upgrade_selected               1     4            objective_resolved             1     2
score_changed                  2     3            state_changed                  1     2
currency_changed               2     1            attack_started                 2     6
combo_changed                  1     2            skill_unlocked                 1     0
pause_changed                  1     3            pickup_collected               1     4
settings_changed               1     5            pickup_spawned                 1     1
save_completed / save_failed   1     2 / 3        projectile_fired               2     5
weapon_equipped / switched     1     3 / 3        skill_cast / skill_ready       1     8 / 3
```

**Zero of the 43 are dead** — every one has at least one emitter in the project. Four
(`skill_unlocked`, `status_expired`, `wave_mutator_applied`, `tutorial_step_completed`) have
no listener today, but they *are* emitted, so deleting them would mean deleting an emit — a
real removal of public event surface, which is what the task explicitly forbids.

**Why safe:** deleting an emitted signal removes a contract other systems may bind to at any
time; a signal with no current listener is a normal part of an event bus. No suppression was
added and no warning category was disabled.

---

## 4. Tests executed

| Gate | Command | Result |
|---|---|---|
| Python regression suite | `python3 -m unittest discover -s tests/python` | ✅ **778 tests, OK** |
| Typed-architecture gate | `python3 tool/check_typed_arch.py` | ✅ clean — 186 project classes, 8 autoloads |
| Guard gate | `python3 tool/validate_guards.py` | ✅ Passed 195, Failed 0 |
| Resource gate | `python3 tool/validate_resources.py` | ✅ Validated 159 files: OK |
| Asset gate | `python3 tool/validate_assets.py` | ✅ 83 models, 90 PNGs, 34 audio, 2 fonts |
| GDScript engine suite | CI `--script res://tests/run_tests.gd` | ⛔ 1095 total / 0 failed as of `eea8bee`; **not re-run since** |

These gates pin exact GDScript source text, so **six pins had to be updated alongside the
renames** — they were failures caught by running the suite, not guesses:
`tool/validate_guards.py:192`, `test_regress_run_modes.py:619,997`,
`test_regress_wave_mutators.py:576`, `test_regress_qa_release_audit.py:456`,
`test_regress_waves_and_spawn.py:22-24`.

`game_mode.gd` is additionally pinned to contain **no authored float magnitudes** (balance
values must live in the data files). Writing the clock as `int(left) / 60.0` tripped that
gate, so seconds-per-minute became a named `const SECONDS_PER_MINUTE := 60` instead of a
`60.0` literal.

---

## 5. Runtime validation performed

From the 4.7.2 CI run at `eea8bee`: the editor booted headless, imported the project, ran the
full GDScript suite (**1095 / 0 failed**), and produced **0 `SCRIPT ERROR`** lines — this is
what proves the three parse errors are gone and that scripts reload. The LSP then opened every
`.gd` and reported 172 warnings / 0 errors.

Runtime warnings in that run that are **not** GDScript diagnostics and are unchanged by this
work: `CharacterVisuals: no VisualRoot/CharacterModel mount point for role basic/splitter`
(×9), `incomplete hero …/WardenGladius.glb` (×3), intentional negative-test noise from
`WaveMutators`/ghost configs (×7), `Parameter "data.tree" is null` at `status_manager.gd:450`
via `test_status_skills.gd:106`, and `38 ObjectDB instances were leaked at exit`. These are
pre-existing and out of scope; flagged here rather than silently rewritten.

**Not re-verified since `192f79c`**, because that requires a push (see §8).

---

## 6. Final Godot diagnostic count

⛔ **Not yet measured.** 172 was the pre-fix baseline. The expected post-fix count is
**43 warnings (all `UNUSED_SIGNAL`), 0 errors**, but I will not state that as a result until
the LSP has actually been re-run against these commits — that is the whole point of the
exercise.

---

## 7. Commits

| Hash | Content | Pushed |
|---|---|---|
| `ab13286` | Shadowing, unreachable code, unused locals (batches 1–3), `RunState.seed`→`run_seed`, `WeaponConfig.range`→`attack_range` + 9 `.tres` | ✅ |
| `4e289e1` | 21 underscore-prefixed unused parameters | ✅ |
| `0165c73` | 19 explicit integer divisions + the `//` fiction-test fix | ❌ local only |
| `192f79c` | Enum casts, scope-conflicting locals, ternary types, 15 redundant awaits, dead `_bus` | ❌ local only |

No suppression of any kind was added: no `@warning_ignore`, no disabled warning category, no
global setting change. `project.godot` still has **no `[debug]` section** — engine defaults.

---

## 8. Push status — **blocked**

`git push origin arena/01a08a34-game-no-7` fails:

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

```
$ gh auth status
  X github.com: authentication failed
  - The github.com token in GH_TOKEN is no longer valid.
```

Both `GH_TOKEN` and `GITHUB_TOKEN` return *Bad credentials* from the API, and an
`x-access-token` URL push is rejected outright. This is a session credential expiry, not a
repository or branch problem — the work is committed locally on
`arena/01a08a34-game-no-7` and nothing is lost. **GitHub needs to be reconnected in Arena**,
after which the two outstanding commits push as-is and the CI gate re-runs the LSP harvest.
