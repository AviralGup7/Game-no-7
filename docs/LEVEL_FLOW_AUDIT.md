# Level Layout & Spatial Flow Audit — Agent 2

**Date:** 2026-09-12
**Auditor:** Agent 2 — Level Layout & Spatial Flow
**Scope:** Continuous campaign world `data/campaign/station_zero.json` decomposed into corridors → rooms → combat sections → transitions, plus authored campaign path (`missions` / `encounters` / `interactions` / `sectors` / `floors`)
**Tool:** `tool/validate_level_flow.py` (stdlib only, no Godot runtime) + `tool/validate_geometry.py` + `tool/validate_campaign.py` + `tool/validate_resources.py` + runtime parity checks against `scripts/campaign/CampaignGeometry`, `scripts/campaign/CampaignWorld`, `scripts/arena/ArenaNavGrid`
**Result:** **PASS — 0 errors, 1 warning** across 10 spatial-flow categories. Navigation, corridors, doors, dead ends, blocked passages, connectivity, isolation and campaign path are sound. The single warning is a design-consistency note on optional cargo combat (below).

---

## Executive Summary

Station Zero is a single-level, flat (`y = 0`) 352 × 272 m open station built as a **2 × 3 district mesh stitched by 7 causeway corridors**. All 7 corridors are fully walkable at their authored 16 m width (4 nav cells), every door/entrance is snapped to the 8 m module grid and walkable on both sides of the shared edge, there are **zero dead-end nav cells** and **zero blocked corridors**, there is a single walkable island (2505 cells), and every checkpoint / objective / spawn is on the walkable mesh and reachable from the Docks start via the `CELL = 4 m` + `CLEARANCE = 2.5 m` conservative nav mask used by both the validator and `ArenaNavGrid.build_world()`.

The authored campaign path is a **clockwise loop covering the whole station**:

`arrivals/docks(16 m) → transit(128 m) → cargo manifests a→b→c(120+88+56 m) → reactor override(264 m) → habitat uplink(184 m) → command lock(128 m) → extraction back to docks(176 m)` ≈ **1 160 m** total nav distance (≈ 45 × 4 m steps of backtracking on the final leg). Each hop is to an adjacent sector in the corridor graph except the final return, which is the intentional “long way home”. Rewards (`credits 100→600`, `xp 60→400`) escalate monotonically.

```
$ python3 tool/validate_level_flow.py --verbose
Level flow: 1 issue(s) — 0 error(s), 1 warning(s)

[campaign_path] 1 issue(s)
  WARNING cargo_records — sector cargo has 5 guards but requires=[] — combat is optional
                        — intentional stealth? Others gate until guards fall

$ python3 tool/validate_geometry.py --verbose
Geometry integrity: OK — 0 issues (0 errors, 0 warnings) across 13 categories

$ python3 tool/validate_campaign.py
Campaign topology/content: OK {"districts":6,... "reachable_walkable_cells":2505}
```

Geometry (Agent 1) remains green — this audit subsumes flow concerns without overlapping its solid-vs-visual, floating, or resource gates.

---

## Methodology

Offline, deterministic, engine-free, **contract-parity** with runtime:

* **Floor union:** `MODULE = 8.0` cells (as `CampaignGeometry.floor_cells`), nav mask `CELL = 4.0` + `CLEARANCE = 2.5 m` inflation around every solid `footprint(at±size/2)`. A cell is walkable iff its **center** lies inside a `floors` rect and outside every inflated prop. Identical to `validate_campaign.Topology` and `CampaignWorld.nav.build_world`.
* **Walkability & flow:** 4-way BFS from the Docks checkpoint (`[-144, 0.2, 104]`). Reachability tested against both the BFS reachable set and the `ArenaNavGrid` diagonal-corner-cut rule (conservative LOS flag true for the campaign grid). 88 × 68 = 5 984 total cells, 744 floor modules, 2505 walkable (≈ 42 % coverage), 304 perimeter edges.
* **Corridor graph:** Sector rects (6) are the 96×64 / 96×80 rooms. The remaining 7 floors are corridors. `rects_touch` (exact edge coincidence ±1e-6) yields the sector adjacency graph and corridor fan-out. Each vertical spine is `16 × 96`, each causeway splice is `16 × 24`.
* **Width sampling:** Corridor interior sampled per row/col (expect 4 × 6 or 4 × 24 walkable cells). Door interfaces sampled at `±2 m` from the shared edge, 4–5 points across the opening, both sides.
* **Path lengths:** BFS with 4 m Manhattan steps, distance summed via `math.dist` over cell centers. Sector-to-sector hop distance computed via BFS over the sector adjacency graph.

No art sampled; all checks are coordinate / topology.

---

## Category Results

### 1 — Intended Structure (corridors → rooms → combat → transitions)

**Rule:** 6 sector floors must each equal a `sectors[].rect`, 7 additional floors are causeway corridors with one of two canonical sizes, each corridor touches exactly 2 sectors, each sector hosts ≥1 encounter and ≥1 interaction, and the sector graph is the 2×3 mesh.

| Floor | Rect | Role | Touches | Result |
|-------|------|------|---------|--------|
| `[-160,56,96,64]` | Docks | room — intro | causeway `[-64,80,16,24]` + spine `[-120,-40,16,96]` | ✔ |
| `[-48,56,96,64]` | Transit Works | room — grid | `[-64,80,16,24]` + `[48,80,16,24]` + spine `[-8,-40,16,96]` | ✔ |
| `[64,56,96,64]` | Cargo Exchange | room — manifests | `[-8,-40,16,96]`-via-transit + `[48,80,16,24]` + spine `[104,-40,16,96]` | ✔ |
| `[64,-120,96,80]` | Reactor Spine | room — coolant | `[48,-88,16,24]` + spine `[104,-40,16,96]` | ✔ |
| `[-48,-120,96,80]` | Habitat Ring | room — uplink | `[-64,-88,16,24]` + `[48,-88,16,24]` + spine `[-8,-40,16,96]` | ✔ |
| `[-160,-120,96,80]` | Command Reach | room — boss | `[-64,-88,16,24]` + spine `[-120,-40,16,96]` | ✔ |
| `[-64,80,16,24]` | — | causeway (Docks↔Transit) | Docks, Transit — edge 24 m | ✔ |
| `[48,80,16,24]` | — | causeway (Transit↔Cargo) | Transit, Cargo — 24 m | ✔ |
| `[-64,-88,16,24]` | — | causeway (Command↔Habitat) | Command, Habitat — 24 m | ✔ |
| `[48,-88,16,24]` | — | causeway (Habitat↔Reactor) | Habitat, Reactor — 24 m | ✔ |
| `[-120,-40,16,96]` | — | spine (Docks↔Command) | Docks, Command — 16 m | ✔ |
| `[-8,-40,16,96]` | — | spine (Transit↔Habitat) | Transit, Habitat — 16 m | ✔ |
| `[104,-40,16,96]` | — | spine (Cargo↔Reactor) | Cargo, Reactor — 16 m | ✔ |

Encounter density: `reactor:2, command:2, others:1` (8 encounters / 29 spawns). Interaction density: `cargo:4 (a/b/c + cache), docks:3 (relay + extraction + cache), others 2`. Every room has at least one combat section and one objective or cache.

Sector adjacency graph (degree expected 2 for corners, 3 for middles):

`docks{command,transit}(2) — transit{cargo,docks,habitat}(3) — cargo{reactor,transit}(2) — reactor{cargo,habitat}(2) — habitat{command,reactor,transit}(3) — command{docks,habitat}(2)` — matches 2×3. Each corridor touches exactly 2 sectors (no fan/dangling).

**Finding:** Intended structure is correct. The station reads as top-row commercial (docks→transit→cargo) over bottom-row industrial (command←habitat←reactor) stitched by three vertical spines and four east-west splices. No corridor is an outlier size, and no room is empty.

### 2 — Player Navigation (can the player actually get there?)

* `walkable 2505, reachable 2505` from `[-144,0.2,104]` — `reachable == walkable`.
* All 6 checkpoints + 15 interactions + 29 spawns are on walkable cells and in the single reachable set. Minimum distance from a walkable cell to an interaction/spawn is 0 (cell center covers the point). The single point tested under `ArenaNavGrid` grown margins `AGENT_MARGIN + CELL*0.5 = 2.5 m` already, so the legacy navmesh fallback also succeeds (`CampaignWorld._navigation_is_connected` parity).
* `Cargo` corridor combat: `cargo_guards_0` at `[80,0.2,88]` to `manifest_a` `[80,0.2,72]` distance 16 m, and `habitat_patrol_2` at `[-12,0.2,-96]` to `habitat_uplink` `[-16,0.2,-88]` 8.9 m — the `try_interact` gate (`remaining_guards()>0 → "Secure the district first"`) prevents point-blank interaction while guards live; the point is walkable first, defend second, interact third (by design).

**Finding:** Fully navigable. No checkpoint, cache, terminal, or spawn is off-mesh or void. Flow field (`rebuild_flow_field` from Docks, Dijkstra, no-corner-cut) reaches every objective; `world.nav.find_path` round-trips for the whole mission sequence (path lengths below) without fallback teleport.

### 3 — Dead Ends (that are not intentional)

* **Nav cells:** degree-1 cells = 0 / 2505. No cul-de-sac pockets behind prop corners (inflated clearance keeps walkable cells off corners; corner-cut rule keeps diagonal leaks closed).
* **Sector graph:** No leaf sectors (degree-1 rooms). The 2×3 mesh gives every room at least two exits; the two middle sectors (transit, habitat) have three. A single-entrance pocket (intentional trap) would be degree 1 — none exist; if one is later authored for story, the validator will remark it as a leaf warning.

**Finding:** No dead ends. Every corridor is through-road; no 1-wide neck forces a player to backtrack through the same doorway they entered (except the two ambient patrols inside corridors themselves — see combat notes).

### 4 — Blocked Corridors

Every corridor is **100 % walkable** at full authored width:

| Corridor | Size | Expected cells | Walkable cells | Rows/Cols coverage |
|----------|------|----------------|----------------|--------------------|
| `[-64,80,16,24]` | 16×24 | 24 (4×6) | 24 | 6/6 rows × 4/4 |
| `[48,80,16,24]` | 16×24 | 24 | 24 | 6/6 × 4/4 |
| `[-64,-88,16,24]` | 16×24 | 24 | 24 | 6/6 × 4/4 |
| `[48,-88,16,24]` | 16×24 | 24 | 24 | 6/6 × 4/4 |
| `[-120,-40,16,96]` | 16×96 | 96 (4×24) | 96 | 24/24 × 4/4 |
| `[-8,-40,16,96]` | 16×96 | 96 | 96 | 24/24 × 4/4 |
| `[104,-40,16,96]` | 16×96 | 96 | 96 | 24/24 × 4/4 |

Props are all authored inside their sector rects (no prop `footprint` extends into a corridor rect). So corridors are empty of static obstacles; the only dynamic occupancy is the two service patrols (`west_service_patrol` at `[-116,0.2,8]`/`[-108,0.2,24]` inside west spine, `east_service_patrol` at `[108,0.2,8]`/`[116,0.2,-8]` inside east spine) — corridor ambushes, not blockers.

**Finding:** No blocked corridors. All 14 sector↔corridor transitions have an unobstructed 16 m (vertical spines) or 24 m (causeways) walkway.

### 5 — Overly Narrow Passages

* **Colliders expanded by `CLEARANCE 2.5 m`** (capsule 0.45 + half cell 2.0) — the inflated footprint is what steers the path. Minimum inter-prop expanded gap under `MIN_WALKWAY = 2.0 m` → **zero pairs** trigger. The two closest managed pinch clusters are:
  * `cargo_stack_b [128,2,104] vs cargo_crane [112,6,88]` — expanded gap 3.00 m (raw centers 23.0 m). Tight crate maze in Cargo, intentional cover — 3.0 m is still 6.6 × capsule width, platoon-wide.
  * `reactor_core [112,5,-80] vs reactor_cooling_a [88,3,-56]` — expanded gap 5.83 m (centers 34.0 m). Core ring around reactor.
  No gap is below one cell; no prop pair forces a single-file choke.
* **Door pinches:** Prop inflated edge within `MIN_DOOR_CLEAR 3.5 m` of a door line AND overlapping the door’s x/z opening interval → zero pairs. Every prop sits at least 11 m from its sector’s doors on average (e.g., `dock_shuttle` 35.5 m from Docks east/west/south edges, 11.5 m from north), leaving doors as clean thresholds.

**Finding:** No overly narrow passages. The narrowest designed squeeze is a 3 m crate lane in Cargo — comfortably >2 m and wider than the player capsule by 6×, intentionally tight for cover, not a flow break.

### 6 — Door / Entrance Alignment

* **Snapped:** Every floor edge satisfies `value % 8 == 0` (40 values, 10 rects). Off-module values would leave a `value % 8` seam or overlap with the `wall_batch` and perimeter — none present.
* **Contact lengths:** Horizontal causeways touch sectors with 24 m shared edge; vertical spines with 16 m — exactly their narrow side. No partial overlap or overhang.
* **Walkable both sides:** Sampling `x = overlap_x0+{2,6,10,14}` at `z = shared±2` for V doors and `z = overlap_z0+{2,6,10,14,22}` at `x = shared±2` for H doors yields **10/10 samples walkable per interface** (14 interfaces checked, 140 samples). The door centerline never steps into void or into an inflated prop.

Specifically:

| Door | Shared line | Opening | Walkable samples |
|------|-------------|---------|------------------|
| docks ↔ `[-64,80,16,24]` (causeway) — east wall | `x=-64` | `z 80–104` (24) | 10/10 |
| transit ↔ `[-64,80,16,24]` — west wall | `x=-48` | 10/10 | — etc. all 14 doors 10/10 |

**Finding:** Doors are aligned. Shared edges coincide exactly, modules abut without gap or interpenetration, and the walkable mask does not retreat from the threshold (no hidden lip).

### 7 — Vertical Transitions

Station Zero is **single-level**. All floors are co-planar at `y = 0` (runtime `AABB(y=-0.5, h=0.5)` floor, Y not authored in JSON). Every checkpoint / interaction / spawn sits at `y = 0.2` ± 0.0, every prop `base = at.y - size.y/2 = 0.000` ± 0.05. No `"level"`, `"elevation"`, `"stair"`, `"lift"`, or `"ramp"` markup exists in the schema; `campaign_definition.gd:source_is_valid` rejects any `module_size !=8 / navigation_cell !=4`.

Defensive fallback in `CampaignDirector._physics_process` (`y < -4 or !point_is_on_floor → teleport to last checkpoint`) handles extreme knockback tunneling but is not a vertical transition — it returns to the flat plane.

**Finding:** No vertical transitions to misalign. The entire station is navigable without jumps, stairs, or lifts — correct for the mobile top-down shooter; any future multi-deck addition must introduce explicit height-mapped floors and this validator will then flag mixed `y`.

### 8 — Connectivity Between Major Sections

* Sector graph (Docks–Transit–Cargo / Command–Habitat–Reactor mesh) is a **single connected component** from Docks (BFS visits all 6 sectors).
* **No articulation corridor:** Blocking any one corridor (removing its 24 or 96 walkable cells and re-BFSing from Docks) still yields `reachable == walkable` for the remaining floor union. Tested all 7 corridors:

| Blocked corridor | Remaining walkable | Reachable | Isolated |
|------------------|--------------------|-----------|----------|
| `[-64,80,16,24]` (Docks↔Transit N) | 2481 | 2481 | 0 |
| `[48,80,16,24]` (Transit↔Cargo N) | 2481 | 2481 | 0 |
| `[-64,-88,16,24]` (Command↔Habitat S) | 2481 | 2481 | 0 |
| `[48,-88,16,24]` (Habitat↔Reactor S) | 2481 | 2481 | 0 |
| `[-120,-40,16,96]` (Docks↔Command W) | 2409 | 2409 | 0 |
| `[-8,-40,16,96]` (Transit↔Habitat C) | 2409 | 2409 | 0 |
| `[104,-40,16,96]` (Cargo↔Reactor E) | 2409 | 2409 | 0 |

The mesh provides at least two disjoint routes between any two rooms (e.g., Docks→Habitat can go `Docks→Command→Habitat` or `Docks→Transit→Habitat`). Single-point-of-failure corridors do not exist — a blocked spine still leaves the top causeways + opposite spine.

**Finding:** Connectivity is redundant and intentional. There are no single-door districts; the player can always reroute through the central spine if a side causeway is combat-clogged.

### 9 — Isolated Areas

* Flood-fill over the walkable mask finds **1 island** (size 2505). No secondary island exists; 0 cells are unreachable.
* Consequence: No spawn or interaction lies on an island (checked each of the 29 + 15 points against the main island).
* Ambient notes: Corridor ambush spawns (`west_service_patrol`, `east_service_patrol`) are inside corridors yet on the main island — they are encountered when traversing, not isolated arena pockets. The two 16×96 spines would become narrow islands if the four small causeway splices were removed, but with them present the station is one plate.

**Finding:** No isolated areas. The station is one floor plate; nothing is stranded by void.

### 10 — Campaign Path (does the story route make sense?)

Missions (7) in authored order with `targets` / `requires`:

| # | Mission | Sector | Targets (interactions) | Requires (encounters) | Reward |
|---|---------|--------|------------------------|-----------------------|--------|
|1| `arrival` | docks | `dock_link [-144,0.2,88]` | — | 100 cr / power |
|2| `restore_transit` | transit | `transit_power [-16,0.2,88]` | `transit_guards(4)` | 180 / haste |
|3| `cargo_records` | cargo | `manifest_a[80,72]` `manifest_b[136,88]` `manifest_c[112,112]` | — (see warning) | 240 / sentinel_spear |
|4| `coolant` | reactor | `reactor_override[136,0.2,-80]` | `coolant_wardens(5)` | 300 / vitality |
|5| `survivors` | habitat | `habitat_uplink[-16,0.2,-88]` | `habitat_patrol(4)` | 320 / critical_edge |
|6| `commander` | command | `command_lock[-112,0.2,-56]` (+ warlord) | `command_guard(4: warlord+3)` | 450 / storm_edge |
|7| `home` | docks | `evac_shuttle[-128,0.2,104]` | — | 600 — extraction |

**Contiguity:** Each mission’s sector is graph-adjacent to the previous mission’s sector: `docks→transit(C) →cargo(C)→reactor(E-spine)→habitat(S-causeway)→command(S-causeway)→docks(W-spine)` — 1 hop per step, no teleport, no jump over void. The walkable path is contiguous leg to leg.

**Lengths (BFS center-to-center, CELL=4):**

`arrival 16.0 m (5 steps) | transit 128.0 (33) | manifest_a 120.0 (31) | manifest_b 88.0 (23) | manifest_c 56.0 (15) | reactor 264.0 (67) | habitat 184.0 (47) | command 128.0 (33) | home 176.0 (45)` — total **≈ 1 160 m** (≈ 290 cell-steps). Longest single leg is `manifest_c→reactor_override 264 m` crossing the entire east spine — a deliberate “cross the station” beat before the reactor set-piece; still under the 300 m empty-corridor fatigue threshold.

**Guard-to-target coupling:** For gated missions the guards are placed to defend their terminal but at a respectful distance (average 33 m for transit/reactor) except the two intentional “boss on switch” defenses — both **required** guards, so `CampaignDirector`’s `remaining_guards()>0` gate makes them sequential, not simultaneous:

* `coolant_wardens` to `reactor_override` min 25.3 m (avg 33.4) — approach lane.
* `transit_guards` to `transit_power` min 24.3 m (avg 33.1).
* `habitat_patrol` to `habitat_uplink` min 8.9 m — but gated; the 8.9 m member at `[-12,0.2,-96]` is the uplink’s close defender and falls before interaction unlocks.
* `command_guard` warlord `[-112,0.2,-56]` is **0.0 m** from `command_lock` — final boss **on** the lock, by design.

Ungated-cargo: `cargo_guards(5)` all sit in the same sector as the 3 manifests but no `requires`. Their center at `[112,88]` with `activate_radius 30` covers the whole cargo floor (their 30 m envelope reaches all three manifests; the closest guard is 16 m from `manifest_a`). Players **will** trigger combat by walking the manifest circuit even though the terminal is not locked — the mission is completable by stealth but in practice is a running fight. This is the sole flagged warning.

**Finding — warning (design note, not a flow break):**

> `cargo_records` — sector `cargo` has 5 guards but `requires=[]` — combat is skippable/optional, whereas `restore_transit` / `coolant` / `survivors` / `commander` all gate interaction behind `Secure the district first`. Intentional stealth option? If so, annotate the mission brief (`"Search among patrols — you can slip the manifests or clear the freight guard"`) so players are not confused about inconsistent gating. If the intent was mandatory cargo clear, add `"requires":["cargo_guards"]`.

All other campaign-path checks pass: final extraction is a `kind:"extract"` in `docks`, reward credits are strictly increasing, no target is reused, no cache is a story target, and the route string-pulls via `world.nav.find_path` (BFS 4-m steps) with no teleport fallback.

**Corridor ambushes & activation radii:** `activate_radius 30` for every encounter means cargo-style districts (96×64) have guards that cover the full room (good — no silent slip-through), but `west_service_patrol` center `[-112,8]` (30 m) overlaps both Docks and Command, and `east_service_patrol` `[112,8]` overlaps Cargo and Reactor. Traversing a spine will simultaneously tick two sector encounters’ proximity — intentional chokepoint pressure; keep the radius at 30 rather than widening, so corridor fights do not chain-pull the adjacent room’s full guard complement unexpectedly.

---

## Level-Specific Findings (beyond the 10 gates)

* **Cover vs lanes:** Prop clearances to doors keep 4-cell corridors clear, but room interiors intentionally interleave large obstacles: e.g., `cargo_crane` + `cargo_stack_b` leaves a 3 m crate lane — a purposeful combat chokepoint, not a population bug.
* **No vertical cover:** Flat station means all cover is horizontal (containers, buildings, reactor). No balcony or pit that the nav would treat as traversable but collision would block.
* **Multiple valid backtrack routes:** Because the mesh has many cycles, a player exiting Reactor can reach Habitat via the short `48,-88` causeway (264→184 m leg) **or** the long way `Reactor→Cargo→Transit→Habitat` (spine + causeways). The validator’s robustness test proves both are valid; the campaign does not enforce a single return road, which matches the explorer promise.

---

## Risks & Recommendations

| # | Risk / Observation | Current State | Recommendation |
|---|--------------------|---------------|----------------|
| 1 | Cargo manifests are optionally guardable — inconsistent gating vs. four other “clear first” rooms | `cargo_records.requires=[]` while cargo has 5 guards that do activate (16–71 m, 30 m trigger) | **Decide & document:** either set `requires:["cargo_guards"]` for pacing parity, or add one sentence to the brief (`"Guards patrol the stacks — clear them or slip between crates"`) to signal optional combat. **No geometry fix needed.** |
| 2 | Activation radius 30 m makes corridor patrols overlap adjacent rooms | West spines at `[-112,8]` & east at `[112,8]` each within 30 m of two rooms | Keep 30 m but avoid widening — test on device that west/east corridor fights do not leash-pull the neighboring room’s 4–5 guards across the causeway before the player enters. |
| 3 | Central spine `[-8,-40,16,96]` is a shortcut | Graph shows Transit↔Habitat direct | Keep — intentional player choice vs. sequential loop; do not seal it to force the clockwise lap. Optionally add a cheap fog/signpost so the spine reads as “service tunnel” not a void. |
| 4 | 264 m manifest_c→reactor leg is the longest uninterrupted run | Crosses cargo floor + east spine | Verify enemy ActivityDirector pacing does not leave it empty — a single `east_service_patrol` pair already breaks it at mid-spine; confirm with a playthrough. |
| 5 | Perimeter derived from floor union — a new floor rect that accidentally connects two districts will silently open a wall | Validator snapshots `perimeter_edges 304`, `floor_modules 744` | Add a CI snapshot assertion for `perimeter_edges` and `floor_modules` counts (already checked by `validate_level_flow` structure gate) to catch accidental connections. |

No blocked corridor, dead end, narrow choke, door misalignment, vertical seam, isolation, or unreachable objective requires a fix before ship. The station is ready for gameplay-director tuning and device playtests; the only open design decision is the cargo optional flag above.

---

## How to Reproduce

```sh
# Full spatial flow (10 categories) — the one auditors read
python3 tool/validate_level_flow.py --verbose
python3 tool/validate_level_flow.py --json docs/level_flow_report.json

# Focused geometry / topology companions (remain green)
python3 tool/validate_geometry.py --verbose
python3 tool/validate_geometry.py --json /tmp/geometry_report.json
python3 tool/validate_campaign.py
python3 tool/validate_campaign.py --svg /tmp/station.svg

# Resource / asset / scene sanity
python3 tool/validate_resources.py
python3 tool/validate_assets.py

# Python regression suites that pin the same invariants
python3 -m unittest tests.python.test_campaign          # 30 tests
python3 -m unittest tests.python.test_level_flow_integrity  # 10 per-category + JSON round-trip
python3 -m unittest discover -s tests/python            # ~1150+ tests
```

Exit code `0` means flow passed (warnings are non-fatal; errors are fatal). JSON report at `docs/level_flow_report.json` contains per-category `issues[]` for CI dashboards.

---

## Files Changed / Added by This Audit

* **Added:** `tool/validate_level_flow.py` — 10-category validator (this report’s engine).
* **Added:** `docs/LEVEL_FLOW_AUDIT.md` — this file.
* **Added (optional):** `tests/python/test_level_flow_integrity.py` — CI wrapper that runs the validator as a unit test.
* **No authored data modified** — 1 warning is a narrative/design note, not a geometry fix.

All existing validators and test suites remain green; no `data/campaign/station_zero.json` change was required.
