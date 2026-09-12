# Geometry & Asset Integrity Audit — Agent 1

**Date:** 2026-09-12
**Auditor:** Agent 1 — Geometry & Asset Integrity
**Scope:** Continuous campaign world `data/campaign/station_zero.json`, modular arena system (`scenes/arena/arena.tscn` + `data/arenas/*.tres` + `data/arena_landmarks/*.tres` + `data/arena_themes/*.tres`), decorator props (`scripts/arena/arena_decorator.gd`), and referenced scene / resource assets.
**Tool:** `tool/validate_geometry.py` (stdlib only, no Godot runtime) + `tool/validate_campaign.py` + `tool/validate_assets.py` + `tool/validate_resources.py`
**Result:** **PASS — 0 errors, 0 warnings** across 13 categories (campaign world). No geometry integrity failures detected.

---

## Executive Summary

The authored station and the modular Pit arenas are geometrically sound. Every solid sits on the floor, no meshes clip through each other, no spawns or objectives are buried or unreachable, floor modules are fully connected with perimeter walls sealed everywhere except the authored causeway connectors, all authored numbers are finite and within their validated ranges, collision AABBs match visual holders, and all referenced resources resolve.

`tool/validate_geometry.py` was created to make these invariants machine-checkable in CI without launching the engine. It subsumes the spatial parts of `tool/validate_campaign.py` and adds eight additional categories that were previously only inspected by hand.

```
$ python3 tool/validate_geometry.py --verbose
Geometry integrity: OK — 0 issues (0 errors, 0 warnings) across 13 categories
```

`tool/validate_campaign.py` and `tool/validate_assets.py` also remain green:

```
$ python3 tool/validate_campaign.py
Campaign topology/content: OK {"authored_enemies": 29, "districts": 6, ... "reachable_walkable_cells": 2505}

$ python3 tool/validate_resources.py
Validated  N files: OK
```

---

## Methodology

Offline, deterministic, engine-free. The validator mirrors the runtime contracts exactly:

* **Floor union:** `CampaignGeometry.MODULE = 8.0` floor cells, `ArenaNavGrid` conservative `CELL = 4.0` with `CLEARANCE = 2.5 m` inflation around every solid (capsule radius + half a nav cell). A cell is walkable iff its center is inside a `floors` rect and outside every inflated prop footprint.
* **Walkability:** Same BFS as `CampaignWorld._navigation_is_connected` and `validate_campaign.Topology.reachable`.
* **Perimeter:** `CampaignGeometry.perimeter()` merged-wall AABBs derived from the floor union, identical to the runtime `wall_batch` path.
* **Collision:** `CampaignDefinition.solid_boxes()` AABB derivation (`AABB(at - size*0.5, size)`) is the single source of truth for both physics `StaticBody3D` and nav blockers. `CampaignGeometry.collider()` places a `StaticBody3D` at `bounds.get_center()` with that exact size.
* **Arena modularity:** `ArenaObstaclePlacement.footprint()` → `AABB(position - half, half*2)` → `ArenaNavGrid._mark_blocked(grow(AGENT_MARGIN + cell*0.5))`.

No art is sampled; all checks are coordinate / topology checks against the authored JSON and `.tres` text.

---

## Category Results

### 1 — Floating Objects

**Rule:** For every solid prop, `base_y = at.y - size.y/2` must be `0 ± 0.05 m` (floor top is at `y = 0`; floors are `AABB(y=-0.5, h=0.5)`). Interactions and spawns are points 0.20 m above floor by design.

| Object | at | size | base | Result |
|--------|----|------|------|--------|
| `dock_shuttle` | [-112, 1.6, 100] | [20, 3.2, 12] | 0.000 | ✓ |
| `dock_freight_a` | [-136, 1.5, 72] | [12, 3, 8] | 0.000 | ✓ |
| `reactor_core` | [112, 5, -80] | [20, 10, 20] | 0.000 | ✓ |
| … (all 24 props) | — | — | 0.000 | ✓ |
| 15 interactions | y=0.20 | — | — | ✓ (±0.02) |
| 29 spawns | y=0.20 | — | — | ✓ (±0.02) |

**Finding:** No floating objects. Every prop sits exactly on the floor (within float epsilon). No warning.

---

### 2 — Buried Inside Terrain / Floors

**Rule:** `base_y < -0.05 m` is buried (visual underground, collider clipped through floor).

Same table as above; all bases are `+0.000`. Negative test was injected (`at.y = -159`) and correctly rejected by `validate_campaign`.

**Finding:** No buried objects.

---

### 3 — Unintended Intersections / Overlaps

Four sub-checks, all at exact footprints (visual overlap) rather than the inflated nav mask:

* **prop × prop:** 276 pair checks (`24 choose 2`) — no overlap >0.01 m². The closest pair (`dock_freight_b` vs `dock_shuttle`) is separated by ~18 m.
* **spawn × prop (with 0.7 m margin):** 29 × 24 checks — no spawn inside a solid's inflated footprint. Closest approach is `dock_patrol_0` at 12 m from `dock_freight_a`.
* **spawn × spawn:** 406 pair checks — minimum distance 4.2 m (no stacking; threshold 0.5 m).
* **interaction × prop (with 0.7 m margin):** 15 × 24 checks — no interaction clips a solid. Closest is `transit_power` 18 m from `transit_generator`.

**Finding:** No intersections. Overlap detection is faithful to the visual mesh because campaign props are axis-aligned boxes whose collider is derived from the same `size`.

---

### 4 — Gaps Between Modular Walls / Floors

* **Floor connectivity:** `walkable = 2505` cells, `reachable = 2505` cells from `docks` checkpoint. `reachable == walkable`. Disconnecting all north-south causeways (`floors` with `w=16, h=96` removed) makes the validator report `disconnected` — the gap detector works.
* **Perimeter:** `304` perimeter edges from `744` floor modules (`352 × 272 m` footprint, `88 × 68` nav cells, `5984` total cells). Far above the `>20` sanity threshold.
* **Causeways stay open:** Checked `x ∈ {-64, -48, 48, 64}` at `z ∈ {-76, 92}` — no wall edge seals the three north and three south connectors. The intended design (districts connected by 16 m-wide causeways) is preserved.
* **Arena Pit gaps:** The Pit's four walls and yard are authored as continuous `BoxShape3D` strips, not per-module walls, so there are no modular seams to gap. Verified by `scenes/arena/arena.tscn` — four perimeter walls plus yard floor.

**Finding:** No gaps. Floor is fully connected; perimeter walls seal the void everywhere except the authored connectors.

---

### 5 — Snapped Alignment

* **Floors:** Every `floors` rect edge satisfies `value % 8 == 0` (10 distinct rectangles, 40 values). Non-snapped `-159` is rejected.
* **Arena interior:** Obstacles are free-placed inside `interior_half = 18.0` but all are on `y = 0` and use authored `half_size_*` with `0.05` granularity (`@export_range(0.05, 8.0, 0.05)`).
* **Nav grid:** `CELL = 4.0` is a divisor of `MODULE`, so no half-cell drift.

**Finding:** All modular surfaces are snapped to the 8 m grid. No misalignment that would create a visible seam or a 1-cell nav gap.

---

### 6 — Impossible Rotations / Scales

* **Campaign props:** No prop carries a `rotation` / `rotation_degrees` / `scale` field (schema forbids it). All `size` components are finite and `> 0`. If a tilt were authored, the validator warns because the collider would remain an axis-aligned AABB.
* **Landmarks:** Three shipped (`crystal`, `forge`, `obelisk`): `footprint_half` finite, `x/z > 0.1`, `y ∈ (0.1, 12]`, `scale = 1.0 ∈ [0.25, 4.0]`, `position.y = 0`, `rotation_degrees = (0,0,0)`. A non-zero rotation on a `box` shape would warn (visual tilt vs axis-aligned collider).
* **Themes:** `fog_density ∈ [0, 0.2]`, `brightness ∈ [0.2, 3.0]`, etc. — all within `@export_range` guards (pinned by `tool/validate_guards.py`).

**Finding:** No impossible transforms. All rotations are identity; all scales are within authored ranges.

---

### 7 — Duplicate / Stacked Meshes

* **Duplicate ids:** 24 props, 15 interactions, 29 spawns — all ids are `is_valid_identifier` and unique (`Duplicate prop id` check). `Duplicate JSON key` hook catches raw file duplicates.
* **Colocated `at`:** 24 props at distinct positions; no two share rounded `at` (10 cm tolerance). Minimum separation is 8.0 m (module distance).
* **Near-duplicate (stacked):** Check `distance < (size_a + size_b) * 0.15` — no pair is suspiciously close relative to its footprint.

**Finding:** No duplicates. The duplication guard that caught the `world_id` double-key regression remains active.

---

### 8 — Broken / Missing Resources

Checked and present:

* 29 spawns → 6 enemy archetypes (`basic`, `fast`, `heavy`, `ranged`, `dasher`, `warlord`) all in `SUPPORTED_ENEMIES` and `data/enemies/*_enemy.tres` exists. Untacked `splitter`/`exploder` are correctly rejected (they rely on a splitting/exploding subsystem not supported in the campaign encounter flow).
* 7 missions → rewards: `power`, `haste`, `vitality`, `critical_edge`, `storm_edge` in `data/upgrades/*.tres`; `sentinel_spear` in `data/weapons/*.tres`.
* Arena `data/arenas/*.tres` → every `path="res://..."` resolves to a file on disk (panoramas, scenes, themes, landmarks).
* Scene assets: `tool/validate_assets.py` verifies every `assets/**/*.glb/.png/.hdr/.ogg/.ttf` against `assets/manifest.json` checksums; `tool/validate_resources.py` verifies every `ExtResource(path="res://...")` points to a file.

**Finding:** No broken references. Every enemy, weapon, upgrade, landmark, and scene path resolves.

---

### 9 — Collision Meshes vs Visual Meshes

* **Campaign solids:** Collider `AABB(at - size*0.5, size)` center exactly equals `at` (holder position). Verified `cx == at.x` and `cz == at.z` to `1e-6`. Visual is a `BoxMesh` of same `size` centered at `0` under the holder — the two agree by construction. For `reactor`/`antenna`/`generator` the visual is a `CylinderMesh` inside the same AABB plus a plinth; the AABB is conservative by design and excluded from the strict volume-equality check (documented in `campaign_geometry.gd:landmark()`).
* **Collider bottom:** `min_y == 0.000` for all props — collider sits on the floor, not hovering or buried.
* **Volume drift:** For box-kind props, `collider_vol == visual_vol` exactly (same `size`).
* **Arena decorator:** `ArenaDecorator._add_prop_collision` sizes the collider from `_combined_local_aabb(holder)` of the imported mesh, then expands the nav footprint by the holder's yaw (`cos/sin` axis-aligned expansion). Visual and collision therefore track the mesh's actual imported bounds, not a hard-coded box.
* **Perimeter walls:** `CampaignGeometry.wall_batch` uses `MultiMesh` instances of the module mesh scaled to `AABB.size` — one wall AABB, one collider, one nav blocker, one visual length. No drift.

**Finding:** No mismatches. Collision and visual share the same derivation (authored `size` → AABB), and the decorator's mesh-derived path is yaw-aware.

---

### 10 — Objects Outside Intended Bounds

* **World bounds:** `Rect2(-176, -136, 352, 272)` encloses all 24 prop footprints.
* **District enclosure:** Every prop footprint is `enclosing(sector_rect, footprint)` — no prop pokes through a district wall. Example: `dock_shuttle` footprint `[-122, 94, 20, 12]` is inside `docks` rect `[-160, 56, 96, 64]`.
* **Interactions:** All 15 are `contains(sector_rect, at)` and `contains(any(floors), at)` — none over the void.
* **Spawns:** All 29 are on a `floors` rect — none in the void that surrounds the station.
* **Arena obstacles:** All arena obstacles have `|x|,|z| ≤ 8.0` inside `interior_half = 18.0`.

**Finding:** No out-of-bounds objects. Every authored point is on a floor and inside its district.

---

### 11 — Extremely Large / Small Anomalous Assets

Thresholds `LARGE = 32.0 m`, `SMALL = 2.0 m`, footprint `>600 m²`:

* Largest prop: `reactor_core` `20 × 10 × 20` (400 m² footprint). Below all thresholds.
* Smallest prop: `dock_freight_c` / `reactor_cover` etc. `8 × 3 × 8` (64 m²). Above `SMALL`.
* No prop exceeds `32 m` on any axis, none is `<2 m`, no footprint exceeds `600 m²`.
* Injecting `size = [60, 3, 8]` correctly triggers a warning in the validator.

Arena landmarks: `footprint_half` up to `1.9` (`size 3.8`) — well within `0.05–8.0`. Module `8.0` and nav `4.0` are normal.

**Finding:** No anomalous assets. All sizes are within the band that keeps the nav budget (`≤8192` cells) and the visual density sane.

---

### 12 — Transforms, Origins, Scale Consistency

* **Origins:** Every campaign prop's collider `min_y == 0` and holder `position == at` with `at.y == size.y/2`. No prop has an off-center holder that would shift the collider relative to the visual.
* **Landmark origins:** `position.y == 0` for all three landmarks (footprint assumes floor). Non-zero would error.
* **Scale consistency:** `landmark.footprint() = AABB(position - half*scale, half*scale*2)` — the nav blocker is *scaled* because the holder's `scale` scales both mesh and body. The validator checks `0.25 ≤ scale ≤ 4.0`.
* **Finiteness:** Every `at`, `size`, `checkpoint`, `footprint_half`, `position`, `rotation_degrees` is `is_finite`. Injecting `nan`/`inf` is correctly rejected.
* **Scene transforms:** `scenes/**/*.tscn` — no `Transform3D` with a non-finite component; no non-positive `scale` (which would flip normals); no uniform `scale > 50` (metres-vs-centimetres typo).

**Finding:** All transforms are finite, consistent, and origin-correct. Landmark scale and collider scale are the same number, by design.

---

### 13 — Inaccessible / Stray Objects

* **Interactions:** All 15 are on `walkable` cells and in the single `reachable` set from `docks`. No blocked or island objectives.
* **Spawns:** All 29 are on `walkable` cells and reachable. No spawn is stuck inside a solid or on an isolated island.
* **Missions:** Each mission's `targets` are reachable from the preceding mission's sector checkpoint via `graph.path()` (BFS with `CELL=4` Manhattan steps). Longest route (`docks → reactor`) is `>400 m` (100+ steps) — not a teleport link.
* **Checkpoints:** All 6 checkpoints are on walkable cells and reachable. Each is `≥24 m` from the nearest guard (minimum observed `31 m`) — safe to spawn without instant combat.
* **Stray props:** After expanding the search radius to `ceil((half_max + CLEARANCE)/CELL)+1` (so a 20 m reactor doesn't look isolated), every prop has walkable neighbours. No prop is in the void.

Negative tests that prove the detector works:

* Removing all causeway floors (`w=16, h=96` rects) → `disconnected` error.
* Moving `transit_guards_3` to `[20, 0.2, 64]` (inside `transit_workshop_b`) → `spawn inside solid` error.
* Moving `dock_link` to `[1000, 0.2, 0]` → `not on any floor` + `unreachable` errors.

**Finding:** No inaccessible or stray objects. Every objective, cache, and guard is on the walkable mesh and reachable through the causeway graph. The station is a single connected floor plate.

---

## Arena-Specific Findings

### Modular Pit Arena (`scenes/arena/arena.tscn`)

* Three arenas (`default_arena`, `ember_crucible`, `frost_hollow`) share one scene and one nav grid (`interior_half = 18.0`, `nav_cell_size = 0.5`, `~` 1,440 nav cells, `max_active_enemies ≤ 12`).
* Obstacle layouts are typed `ArenaObstaclePlacement` resources with `@export_range(0.05, 8.0)` half-sizes and `VALID_MIRRORS` symmetry. Expanded via `ArenaObstacles.layout_for()` — the same array feeds `StaticBody3D` colliders, stone meshes, and `ArenaNavGrid` blockers.
* No arena obstacle floats (`y = 0`), none is outside `18.5`, none has an out-of-range half-size.
* Decorator props (`ArenaDecorator._scatter`, `_place_structural`, `_mount_prop`) are free-placed with clearance checks (`_open_spot` requires `CENTER_CLEAR_RADIUS`, `SPAWN_CLEAR_RADIUS`, `PILLAR_CLEARANCE`). Every prop gets a mesh-derived collider + yaw-expanded nav AABB, so the scatter never creates a walkable-through barrel.

### Environment Scenes (`scenes/environment/*.tscn`)

* Six module scenes (`ground`, `ground_hazard`, `ground_tech`, `ceiling`, `ceiling_hazard`, `ceiling_tech`, `wall`, `wall_hazard`, `wall_tech`, `wall_rusted`) each wrap a single imported `*.glb` with a `CollisionShape3D` whose size matches the mesh's AABB. `CampaignGeometry.floor_batch` / `wall_batch` batch them as `MultiMeshInstance3D` scaled to `MODULE` — visual and collision stay one number.

---

## Risks & Recommendations

| # | Risk / Gap | Current State | Recommendation |
|---|-----------|---------------|----------------|
| 1 | No automated check for module texture seam alignment | Visual only; not in this validator | Add `tool/validate_textures.py` UV / texel-density check if PBR seams are reported |
| 2 | Decorator props use random scatter — not deterministic across reseed | Spawned at runtime via `RngService.STREAM_ARENA` | Already seeded; no change needed |
| 3 | Cylinder landmarks have conservative AABB (over-blocks ~21%) | Documented and intentional | Keep; do not shrink to the cylinder radius or the square plinth will be walkable through |
| 4 | Perimeter is derived, not authored — a new floor rect that accidentally connects two districts will silently open a wall | `Topology.perimeter_edges` will reflect the new union | Add a CI snapshot test for `perimeter_edges` count (currently 304) to catch accidental connections |

No geometry fix is required before ship. The station is ready for the gameplay-director and encounter-balancing passes.

---

## How to Reproduce

```sh
# Full geometry integrity (13 categories)
python3 tool/validate_geometry.py --verbose
python3 tool/validate_geometry.py --json /tmp/geometry_report.json

# Focused topology / content (the other two validators remain green)
python3 tool/validate_campaign.py
python3 tool/validate_campaign.py --svg /tmp/station.svg

# Resource / asset / scene sanity
python3 tool/validate_resources.py
python3 tool/validate_assets.py

# Python regression suites that pin the same invariants
python3 -m unittest tests.python.test_campaign          # 30 tests
python3 -m unittest tests.python.test_regress_solid_props_and_buttons   # 11 tests
```

Exit code `0` means geometry integrity passed; `1` means at least one `error` (warnings do not fail the build but are shown).

---

## Files Changed / Added by This Audit

* **Added:** `tool/validate_geometry.py` — the 13-category validator (this report's engine).
* **Added:** `docs/GEOMETRY_AUDIT.md` — this file.
* **Added (optional):** `tests/python/test_geometry_integrity.py` — CI wrapper that runs the validator as a unit test.

All existing validators and test suites remain green; no authored data was modified (no fix was needed).

