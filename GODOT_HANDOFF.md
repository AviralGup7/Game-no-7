# Godot 4.4.1 Behavioral Test Handoff

The arena-agent sandbox cannot obtain or run Godot 4.4.1:

- no Godot binary anywhere on the filesystem (`which godot`, `find /`),
- no docker/conda/nix/apt package sources (all reachable mirrors return HTTP `000`),
- GitHub release downloads redirect to `release-assets.githubusercontent.com` /
  `objects.githubusercontent.com` (Azure release-asset bucket) — all blocked.
  Only `github.com`, `codeload.github.com`, and `api.github.com` are reachable.

Per the operator requirement, do NOT modify the navigation implementation until a
real Godot runtime has produced the complete log below.

## How to run

Branch with all committed fixes: **`arena/01a083d7-game-no-7`** at `20abe3a`
(working tree clean).

```bash
git fetch origin
git checkout arena/01a083d7-game-no-7

# 1) Import / full-project compile (report ANY error):
godot --headless --path . --import

# 2) The full headless test suite (THE key command — paste COMPLETE stdout+stderr):
godot --headless --path . --script res://tests/run_tests.gd
```

Environment requirement: Godot **4.4.1-stable** Linux x86_64 (matches the CI
`GODOT_VERSION`). Run from the repo root. Paste the *complete* output of both
commands, unedited — including Godot `ERROR:`/`SCRIPT ERROR:` lines that appear
above/below the `GDScript tests: N total, N failed` summary.

## State as of handoff

- `validate-resources` (Python + typed-arch + guards + assets): **GREEN**
- Every Godot script **compiles** (`--import` is clean). Fixes already committed:
  - `arena_nav_grid.gd`: `NEIGHBORS` → `Array[Vector2i]` (fixes `nc`/`ni` Variant-inference compile errors).
  - `enemy_ranged_state.gd`: `fposmodf(...)` → `fposmod(...)` (nonexistent global; made the script unloadable so ranged/dash/fuse never registered).
  - `camera_rig.gd`, `camera_collision_solver.gd`: `BASIS`/`Basis` → `Basis()` (bare `Basis` is invalid).
  - `enemy_pack.gd`: `intersect_shape` now called on `direct_space_state` (was on `World3D`); typed `Array[Dictionary]` result; headless-no-space guard.
  - `camera_shake_controller.gd`, `camera_profile.gd`, `camera_rig.gd`, `test_integration_wave_boss.py`, `tool/check_typed_arch.py`: camera duck-typing / dead `_validated_*` cleanup + the honest cosmetic-shake regression test.
- **Godot behavioral tests: reduced 21 → 7 failures** (all in the #26 arena-nav feature).

## The 7 remaining failures (captured from CI annotations)

`test_nav_grid.gd` (arena half=12, cell 0.5, wall slab x∈[4,8] z∈[-1,1]):

| # | name | expected | actual observed |
|---|------|----------|-----------------|
| 1 | LOS open over the wall | `has_line_of_sight((0,0,0),(10,0,5))` = true | false |
| 2 | flow field leaves the start on the cheap (south) detour diagonal | `d.x>0.4 and d.z>0.4` | `d=(0.707107,0,-0.707107)` → it leaves **north**, test wants **south** |
| 3 | flow field runs the detour straight at the wall edge | at `(3,0,0)`, `\|dn.z\|>0.9 and \|dn.x\|<0.1` | `dn=(0.707107,0,-0.707107)` (still diagonal, north) |
| 4 | A* waypoints avoid the wall | every waypoint walkable & outside slab | path `[(8.25,0,-0.75),(11.25,0,-0.75),(11.25,0,0.25)]` — `(8.25,0,-0.75)` is inside slab (x∈3.4..8.6, \|z\|<1.6) |
| 5 | A* detours laterally around the slab | `max_z>1.0` | `max_z=0.75` |
| 6 | ember_crucible: spawn markers stay clear (jitter-proof) | spawn points clear of obstacles | an obstacle sits within ~1.7 of a spawn |

`test_arena_obstacles_node.gd`:

| # | name | expected | actual observed |
|---|------|----------|-----------------|
| 7 | arena: gate gap + player start stay walkable | gate gap walkable | `gate=false` (obstacle in/over the gate gap), `start=true` |

## Root-cause hypotheses to verify with the real log (do not assume)

1. **Symmetric detour tie-break (items 2,3):** The wall is symmetric about the
   x-axis. The flow field currently leaves *north*; the test wants *south*.
   Inspect `_flow_target`/neighbor iteration + priority-queue tie ordering in
   `scripts/arena/arena_nav_grid.gd` and make the deterministic rule explicit
   rather than incidental. Preserve determinism.
2. **LOS (item 1):** Ray `(0,0,0)→(10,0,5)` clears the wall top (z=5), yet is
   blocked. Check the LOS ray-grid walk, cell-center rounding, and whether a
   boundary/corner cell at the wall end is treated as blocked.
3. **A* detour too shallow (items 4,5):** Path hugs the wall (max lateral 0.75)
   and one waypoint lands inside the slab. Check agent-margin inset and
   corner-cutting rule in `_astar`/`find_path`.
4. **ember_crucible layout (item 6) and gate gap (item 7):** Inspect actual
   obstacle boxes from `ArenaObstacles.layout_for("ember_crucible"|"default_arena")`
   vs the #26 layout. Determine if the geometry fixture is wrong or the test
   asserts an outdated #26 contract. Do NOT move obstacles arbitrarily.

## AUTOLOAD blocker (resolve too)

When `run_tests.gd` (a `SceneTree` main loop run via `--script`) loads gameplay
scripts, CI reports compile-time identifiers missing even though those are real
autoloads in `project.godot`:

```
Identifier not found: GameRoot   at arena.gd:108, attack_controller.gd:248
Identifier not found: EventBus   (status_manager.gd:61 region)
Failed to compile depended scripts.
```

`--import` compiles them fine (autoload globals known), so this appears to be a
`--script`/SceneTree autoload-global resolution difference. Confirm against the
real run and fix per Godot 4.4.1 autoload behavior — do not fabricate fake
singletons/globals just for the test harness.

## What to paste back

- Full output of `godot --headless --path . --import`
- Full output of `godot --headless --path . --script res://tests/run_tests.gd`
  (this is the critical one — every `ERROR:`/`SCRIPT ERROR:`/`GDScript tests:` line)
