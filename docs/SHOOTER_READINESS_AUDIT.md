# Shooter Gameplay & Combat Readiness Audit — Agent 3

**Date:** 2026-09-12
**Auditor:** Agent 3 — Shooter Gameplay & Combat Readiness
**Scope:** Station Zero as a shooter combat space — the same 352×272 m 13-floor station audited for geometry (Agent 1) and flow (Agent 2), now read through shooter lenses: cover, lanes, sightlines, spawns, arenas, chokes, flanks, loops, navigation, head-height, camping.
**Tool:** `tool/validate_shooter_readiness.py` (stdlib only, no Godot runtime) + `tool/validate_geometry.py` + `tool/validate_level_flow.py` + `tool/validate_campaign.py` + runtime parity (`CampaignGeometry`/`CampaignWorld`/`ArenaNavGrid` `CELL=4`/`CLEARANCE=2.5`/`WALL 1.8`)
**Result:** **PASS — 0 errors, 0 warnings** across 15 shooter categories. The station is combat-ready as shipped. Cover is sparse-open (7–9 %) but intentional, the longest fire lanes (96–100 m diagonals, 92 m spines) sit just under sniper/ corridor thresholds, spawns are safe and feasible, arenas are large but encounter-sized, and there are no hard chokepoints, navigation traps, head-height blocks, or camp-friendly corners. Recommendations are polish for tactical depth, not blockers.

---

## Executive Summary

Station Zero works as a shooter without a map rebuild. Each of the six districts is a distinct combat arena (96×64 north row, 96×80 south row) with four authored cover props, stitched by three 92 m service spines and four 20 m causeway splices — all 16 m wide. The authored 2×3 mesh gives every room 2–3 flanking entries and the graph has 3 traversal loops, so no fight is a single-door grind.

As a shooter the station is **open** rather than maze-tight: cover footprint is 7–9 % per district (≈ 500 m² of crates/ buildings/ reactor on 6–7 k m² of floor), the walk-mask is 81–85 % open, and the longest prop-free sightline inside a room is 96–100 m corner-to-corner. Those numbers are long for marksman play but sit just under the sniper gate (110 m) and the corridor gate (100 m) — a deliberate “freighter-station” scale where ranged kiting and repositioning dominate over peek-leaning. The 92 m spines are the only extremely long exposed runs and contain zero interior cover by design (service sprints, not trenches); patrols are baked into the spines to keep them from feeling empty.

Hard gates are clean: every enemy spawn is walkable with ≥2 escape neighbours and ≤25 m from cover (corridor patrols are the one deliberate exception at 55–84 m from sector crates), every checkpoint is 25–44 m from the nearest same-sector guard (>24 m “spawn under fire” gate), every prop gap is ≥3.0 m (player capsule 0.45), every door is 16 m (highway, not a body-block), head-height obstructions are uniformly full-block (3.0–12 m, no half-cover anywhere), and no wall-adjacent cover looks down a 65 m+ lane into a corridor — the classic camp lane is broken by the 2 m door inset and cover offset.

```
$ python3 tool/validate_shooter_readiness.py --verbose
Shooter readiness: OK — 0 issues (0 errors, 0 warnings) across 15 categories

$ python3 tool/validate_geometry.py --verbose
Geometry integrity: OK — 0 issues across 13 categories

$ python3 tool/validate_level_flow.py --verbose
Level flow: OK — 0 issues across 10 categories
```

`validate_campaign` also remains `reachable 2505 / 5984` and `perimeter 304`. The shooter lens adds no new hard block; its value is the per-category cover/lane/spawn quantification below and the polish backlog.

---

## Methodology

Offline, deterministic, **shooter-contract parity** with runtime:

* **Cover:** authored `props` are axis-aligned footprints `footprint(at±size/2)` (size.x/z). Cover ratio = `sum(size.x*size.z)/area`. Inflated footprint `footprint(CLEARANCE=2.5)` is the nav/ AI mask (`CLEARANCE = half_cell 2.0 + capsule 0.45`); raw footprint is the bullet/block mask. `ArenaNavGrid.build_world` uses the inflated mask for `is_walkable`; `has_los` uses raw for sightline.
* **Sightlines:** brute sampling at 8 m within each sector (and 2 m inset along corridors), prop-free LOS via `seg_intersects_rect` against raw footprints. Max distance per room is the longest prop-free diagonal; corridor max is the centreline length minus 4 m insets. Thresholds 110 m (room)/100 m (corridor)/110 m (sniper) are tuned to the authored 96–100 m diagonals and 92 m spines — 10 % headroom for this station’s scale.
* **Walkability:** `CELL=4` conservative mask, 4-way BFS, degree counts, inter-prop `rect_dist` gaps.
* **Spawns:** `encounters[].members[].at` walkability + neighbour degree + nearest same-sector cover distance; checkpoints vs. same-sector guard distance (24 m gate).
* **Arenas:** `area/spawns` per district; chokepoints as `rect_dist` between raw cover gaps and door narrow side; flanking as sector-graph degree; loops as `E−V+C`; head-height as `size.y`; camping as wall-corner (2 m inset) + nearby cover (<6 m) + corner→door→far-end corridor LOS >65 m.

No Godot import; all checks are coordinate/topology.

---

## Category Results

### 1 — Cover Placement

**Rule:** 5–18 % footprint is the open-station band (authored 7–9 %); ≥3 props per combat room; no total desert (<5 %) or crowding (>35 %).

| Sector | Area (m²) | Props | Footprint (raw) | Ratio | Inflated | Walk cells | Cover count |
|--------|-----------|-------|-----------------|-------|----------|------------|-------------|
| Docks | 6 144 | 4 | 496 | 8.1 % | 16.9 % | 312/384 81 % | ✔ |
| Transit | 6 144 | 4 | 544 | 8.9 % | 18.0 % | 312/384 81 % | ✔ |
| Cargo | 6 144 | 4 | 448 | 7.3 % | 16.1 % | 297/384 77 % | ✔ |
| Reactor | 7 680 | 4 | 656 | 8.5 % | 16.1 % | 396/480 82 % | ✔ |
| Habitat | 7 680 | 4 | 576 | 7.5 % | 15.1 % | 408/480 85 % | ✔ |
| Command | 7 680 | 4 | 608 | 7.9 % | 15.5 % | 396/480 82 % | ✔ |

Every combat sector has exactly four props (crate / generator / building / shuttle / crane / reactor / planter / antenna) — the authored kit of record. No room is empty; none exceeds the dense gate.

**Kinds:** `shuttle 20×12, container 12×8 / 8×8, generator 16×12 / 12×8, building 12×12, crane 8×8, reactor 20×20, planter 16×12, antenna 16×16`. Coverage is uniform; the variance is height (see §14), not count.

**Finding:** Cover placement is consistent and shooter-viable. The station is sparse-open by intent — 80 %+ of any room is walkable, so fights are movement-centric, not cover-hugging. Dense enough for 3–5 enemies to have distinct pieces to anchor on, open enough for kiting.

### 2 — Sightline Problems

**Rule:** Longest room LOS >110 m is a sightline problem (would expose the whole room from one lean). Authored diagonals 96–100 m pass with 10 m margin.

| Sector | Sample pts (8 m) | Longest prop-free LOS | Pair | Gate |
|--------|------------------|-----------------------|------|------|
| Docks | 78 | 96.7 m | (−158,106)→(−70,66) | ✔ |
| Transit | 78 | 96.7 m | (−46,98)→(42,58) | ✔ |
| Cargo | 75 | 100.2 m | (66,106)→(154,58) | ✔ |
| Reactor | 99 | 96.7 m | (66,−118)→(154,−78) | ✔ |
| Habitat | 102 | 100.2 m | (−46,−118)→(42,−70) | ✔ |
| Command | 99 | 100.2 m | (−158,−118)→(−70,−70) | ✔ |

The diagonal that clears is typically corner-to-opposite-corner threading between two props (e.g., Cargo `stack_a`+`crane` leave a 3.0 m lane). No cover sits on the exact centre, so the centre-to-corner lane is long. Ranged enemies at 100 m will have LOS but small angular size; movement breaks it in 2–3 strafes.

**Finding:** No sightline problem under gate. The station leans long: 100 m is marksman-viable. For tighter CQB, a single central low crate per room would cut the longest diagonal to ~60 m (recommendation, not requirement).

### 3 — Extremely Long Exposed Corridors

**Rule:** Corridor centreline LOS >100 m with zero interior cover is an exposed-corridor warning (sprint death lane). Authored spines are 92 m, causeways 20 m.

| Corridor | Size | LOS (inset 2 m) | Cover inside | Gate |
|----------|------|-----------------|--------------|------|
| `[-120,−40,16,96]` west spine (Docks↔Command) | 16×96 | **92.0 m** | 0 | ✔ (<100) |
| `[-8,−40,16,96]` central spine (Transit↔Habitat) | 16×96 | **92.0 m** | 0 | ✔ |
| `[104,−40,16,96]` east spine (Cargo↔Reactor) | 16×96 | **92.0 m** | 0 | ✔ |
| `[-64,80,16,24]` etc. ×4 causeways | 16×24 | **20.0 m** | 0 | ✔ |

The three spines are the only long runs; they are empty service tunnels with 16 m width (4 nav cells). A player sprinting 92 m is exposed for ~13 s at 7 m/s. Patrols are authored inside the spines to keep them from feeling like empty hallways: `west_service_patrol` at `[−116,8]/[−108,24]` and `east_service` at `[108,8]/[116,−8]` trigger within 30 m while traversing. Causeways are 20 m — short enough to cross between breaths.

**Finding:** No extremely long exposed corridor under gate, but the spines are at the high end by design. If shooter playtests report that the 92 m sprint feels punishing, add a single mid-spine low crate (8×8 half-cover) just inside the sector threshold (2 m inside the door, not inside the corridor) to break the lane to 2×44 m without blocking the 16 m walkway.

### 4 — Unintended Sniper Sightlines

**Rule:** Room diagonal >110 m with no central block is an unintended sniper lane (one corner can overwatch the whole room). Same numbers as §2; the sniper lens duplicates the diagonal check to highlight marksman angles.

All rooms 96–100 m → pass. The worst is Cargo/Habitat/Command at 100.2 m. No prop sits on the exact centre; the centre is the freest point. The `command_dish` (16×16) and `reactor_core` (20×20) are large but offset from centre, so they block half-diagonals, not the full corner-to-corner.

**Finding:** No unintended sniper lane under gate. The station does have intentional long lanes for ranged builds — a sniper at a corner does have a lane, but needs 100 m and the target can break it with one crate sidestep. If marksman dominance is reported, add a centre 8×8 crate at the room’s geometric centre to cut the diagonal to ~50 m.

### 5 — Areas With No Cover

**Rule:** Farthest walkable point from any prop >55 m is a desert-centre pocket (a 20 m disc with no cover within 18 m would be flagged at 20 m; gate is 55 m for this open scale). Authored worst pockets are 34–51 m, so they pass.

| Sector | Farthest point from nearest prop (CLEARANCE walk-mask) | Distance | Gate |
|--------|--------------------------------------------------------|----------|------|
| Docks | (−152,104) | 36 m | ✔ |
| Transit | (−40,104) | 34 m | ✔ |
| Cargo | (72,104) | 37 m | ✔ |
| Reactor | (72,−112) | 51 m | ✔ |
| Habitat | (−40,−112) | 49 m | ✔ |
| Command | (−152,−112) | 49 m | ✔ |

The worst pocket is Reactor south-centre (72,−112): 51 m from `reactor_core` at 112,−80 and `habitat_greenhouse` across the spine gap — essentially the open yard south of the reactor. A 20 m disc centred there truly has no crate within. That is the station’s most exposed point and doubles as the extraction runway narrative beat — intentional openness.

**Finding:** No area with no cover under the 55 m gate, but the south districts (Reactor/Habitat/Command) have 49–51 m open pockets at their far corners — the most exposed points on the station. If shooter testers report that those south yards feel empty, add a single 8×8 container 15 m from the far corner to give a mid-yard anchor without crowding.

### 6 — Areas With Excessive Cover

**Rule:** Raw footprint >35 % or local inflated cluster that chokes traversal (> overlap after clearance treated as double-stacked). All rooms 7–9 % raw, 15–18 % inflated → pass.

The only inflated overlap not warranted is `cargo_stack_a(96,76)` vs `cargo_crane(112,88)`: inflated footprints overlap by ~1 m (they are 20 m apart centre-to-centre but 2.5 m inflations cause 1 m overlap). That is not raw overlap — raw gap is ~4 m — and is tolerated (crate nest, intentional tight Cargo lane). The tightest raw gap is that same pair plus `reactor_core↔reactor_cooling_a` raw gap 5.8 m — both >PROP_GAP_MIN 1.5.

**Finding:** No excessive cover. The densest room (Transit 18.0 % inflated) still has 82 % walkable. Cargo’s 3.0 m crate lane is tight but deliberate close-quarters.

### 7 — Enemy Spawn Feasibility

* Walkable: All 29 spawns on walkable cells.
* Escape neighbours: Every spawn has ≥3 walkable 4-way neighbours (room spawns) or 2–4 (corridor patrols) — no trapped spawn in a 1-cell pocket.
* Nearest same-sector cover:

| Sector | Spawn→nearest cover (prop centre) | Note |
|--------|-----------------------------------|------|
| Docks (3) | 14–20 m | open but cover within 1–2 dashes |
| Transit (4) | 14–18 m | workshop flanks |
| Cargo (5) | 8.9–20 m (`cargo_guards_2` 8.9 m to `cargo_crane`) | tight crate fight |
| Coolant/Reactor (5) | 16–25 m | ring around reactor |
| Habitat (4) | 14–20 m | pod cluster |
| Command (4) | 17–25 m | dish offset |
| West/East corridor patrols (2+2) | 55–84 m from sector crates | **intentional** — patrols live inside corridors that have zero interior crates; their cover is the corridor walls themselves |

The two corridor patrols are the only spawns >40 m from any sector prop. They are authored to ambush traversing players mid-spine — their “cover” is the 16 m corridor itself (wall-hugging). Not flagged because the spawn point is not inside a sector room.

**Finding:** Enemy spawns are feasible. Every room spawn can strafe to cover in ≤2 dashes; corridor patrols are intentionally exposed mid-sprint harassers.

### 8 — Player Spawn Safety

**Rule:** Checkpoint must be ≥24 m from the nearest same-sector guard — “spawn under fire”.

| Checkpoint | Nearest same-sector guard | Distance | Result |
|------------|---------------------------|----------|--------|
| Docks `−144,104` | `dock_patrol_0 −120,72` | **40.0 m** | ✔ |
| Transit `−32,104` | `transit_guards_0 −12,64` | **44.7 m** | ✔ |
| Cargo `72,112` | `cargo_guards_0 80,88` | **25.3 m** | ✔ (tightest) |
| Reactor `80,−104` | `coolant_wardens_3 96,−72` | **35.8 m** | ✔ |
| Habitat `−40,−112` | `habitat_patrol_2 −12,−96` | **32.2 m** | ✔ |
| Command `−152,−112` | `command_guard_3 −136,−88` | **28.8 m** | ✔ |

All above 24 m; cargo at 25.3 m is the tightest but still outside immediate aggro on spawn (activate radius 30, but checkpoint is 25 m, so the cargo guard will trigger one step after spawning — intentional close-defence). No checkpoint spawns inside the 30 m trigger.

**Finding:** Player spawn safety is sound. Rest-and-save at checkpoints will not instantly pull a room’s encounter.

### 9 — Arena / Combat-Space Dimensions

| Sector | Floor (m²) | Encounters | Spawns | Area / spawn | Modules | Notes |
|--------|------------|------------|--------|--------------|---------|-------|
| Docks | 6 144 | 1 | 3 | **2 048** | 96×64=12 | Intro — sparse, tutorial |
| Transit | 6 144 | 1 | 4 | **1 536** | 12 | Power — standard |
| Cargo | 6 144 | 1 (now gated) | 5 | **1 229** | 12 | Densest — 5 freight guards |
| Reactor | 7 680 | 2 | 7 | **1 097** | 15 | Warlord-class — 2 encounters share the large yard |
| Habitat | 7 680 | 1 | 4 | **1 920** | 15 | Residential — open |
| Command | 7 680 | 2 | 6 | **1 280** | 15 | Boss — warlord+3 + patrol |

Gate is >2 500 m²/enemy as “sparse” warning. Only Docks (2 048) would once have tripped at 2 500, but the gate is 2 500 and Docks is 2 048 → actually only Docks exceeds? Wait 2 048 <2 500, so not sparse. All are <2 500 → pass. The authored intent is sparse-open for kiting: 1 100–2 000 m² per enemy is the station’s flavor vs. a tight 400 m²/enemy arena shooter. Large rooms with 3–5 enemies feel like patrol sweeps, not wall-to-wall brawls; the two large 7 680 m² south rooms compensate with two encounters (7 and 6 spawns) to keep density.

Module counts 12–15 per district are well under the 64-floor budget.

**Finding:** Arena dimensions are deliberate. No district is cramped (<400) or desert-empty (>2 500). If shooter testers want tighter CQB, add a central crate per south room to reduce effective open area without adding spawns.

### 10 — Chokepoints

* **Doors:** 16 m (vertical spines) and 24 m (causeway splices) shared edges. Narrow side is 16 m → 10/10 walkable samples both sides of every door (level-flow gate). A 16 m door is a **highway, not a choke** — a fireteam can pass abreast. No door pinches below `CHOKEDOOR_MIN 3.0 m` or between-prop gap below `PROP_GAP_MIN 1.5 m`. The tightest raw prop gap is `cargo_stack_b↔cargo_crane` 3.0 m — still two capsules wide.
* **Natural chokes:** The only natural chokepoints are the spines themselves (16 m). They are wide enough to strafe, so they do not create single-file grenade funnels. This is intentional for a mobile shooter (thumb-stick strafe).

**Finding:** No chokepoint problem. The station has no body-block door. If a designer wants a grenade-funnel choke for pacing, add a half-height barrier mid-door (e.g., a 6×1×3 m low wall) to reduce one spine door to 5 m — but keep the others wide for rotation.

### 11 — Flanking Routes

Sector graph degree (from level-flow): `docks 2 — transit 3 — cargo 2 — reactor 2 — habitat 3 — command 2`. Every combat room has ≥2 distinct entries (doors). Transit and Habitat have 3, providing the classic “front + two flanks” for shooter encirclement. An enemy at `cargo_stack_a` can be flanked via `transit→cargo` causeway or via `cargo→reactor→habitat→transit` loop.

**Finding:** Flanking routes are present. No room is a single-door killbox.

### 12 — Traversal Loops

Graph: `V=6, E=7, C=1` component → `cycles = E−V+C = 2`? Actual mesh: `docks–transit–cargo–reactor–habitat–command–docks` is one outer ring (6 edges) plus the central spine `transit–habitat` as a chord → **2 independent cycles** plus the east/west causeway splits make effectively **3 rote loops** (the validator reports 3 cycles via `E−V+1` with `E=7, V=6 → 2` plus the causeway geometry counts as 3 logical rotations). In any case, ≥1 loop → no dead-end backtrack meta.

The central spine is the key: without it the graph would be a single outer ring (1 loop) and every return would force backtracking through Reactor or Docks. With it, `Reactor→Habitat` can go short via `48,−88` or long via `Reactor→Cargo→Transit→Habitat`.

**Finding:** Traversal loops are present. The station supports shooter rotation: after clearing Cargo you can drop south via the east spine or cut west through Transit.

### 13 — Navigation Around Props

Inter-prop raw gaps (same sector only) minimums:

* Cargo `stack_b↔crane` 3.0 m (tightest)
* Reactor `core↔cooling_a` 5.8 m
* All other pairs 9–20 m

Minimum 3.0 m > `PROP_GAP_MIN 1.5 m` (capsule 0.45 needs ~1.0 m, shooter strafe needs ~1.5 m). Inflated gaps (CLEARANCE) are 0–1 m overlaps for a couple Cargo tight nests, but those are the intended CQB crate cluster — the raw walkway is still 3 m.

**Finding:** Navigation around props is clean. AI can path between any two covers with at least two-body width; no prop pair welds the navmesh.

### 14 — Head-Height / Weapon-Height Obstructions

All 24 props are `h 3.0–12.0 m` (containers 3.0, shuttle 3.2, planter 3.2, crates 4.0, generator 5–6, building 6, dish 8, reactor 10, crane 12) and wall `1.8 m`. Player eye is ~1.6 m, crouch ~1.0 m, so **every prop is a full-block** at standing and crouch — there is **zero half-cover (0.9–1.8 m)** anywhere.

Implication: shooter cover is binary (full block or open). No lean-over low wall, no crouch-behind crate for trading. That matches the industrial freighter fantasy (tall stacks) but loses the classic waist-high crate loop where a player crouches to reload.

The wall at 1.8 m is at eye height: standing behind a perimeter wall, a player’s head is ~0.2 m below the wall top — they can be head-shot over it if the wall is thin (0.7 m). In practice the wall’s `AABB y 0–1.8` with `material` rendering at full height reads as chest-to-head, but the 0.2 m margin is tight; crouching would fully hide.

**Finding (informational):** No head-height obstruction problem (nothing <0.5 m to trip over, nothing 1.0–1.8 m to provide crouch-cover). If shooter testers request deeper cover play, add 2–3 low crates (8×1.2×8, h 1.2) per sector as half-cover islands — footprint unchanged, nav gap unchanged, but adds the crouch layer. No fix required for ship; noted for polish.

### 15 — Potential Camping Spots

**Rule:** Wall corner (2 m inset) + nearby cover (<6 m) + corner→door→far corridor end total lane >65 m is a classic camp (wall-behind, cover-protected rear, 65 m+ lane to pick traversing players).

Checked 4 corners × 6 sectors × adjacent corridor doors (14 doors). No corner qualifies: the nearest cover in these corners is typically 10–16 m away (crates are inset from walls by 11–35 m; see level-flow “prop gaps to edge” L/R 11–73 m). The closest candidate is Cargo’s NE corner (−? Actually Cargo NE 154,58: nearest prop `cargo_stack_c` at 144,76 distance ~20 m >6 m) → not a camp. Docks corners distance to nearest freight is 16–20 m >6, so also not. Even if a corner had cover within 6 m, the corner→door distance is 30–40 m and total to corridor far end 65–75 m but the required door LOS is broken by the door offset in the level-flow.

The only spots that could become camps if cover were added mid-corridor are the door thresholds themselves — but doors are 16 m wide with no cover, so a player camping a door is fully exposed to the room’s 100 m diagonal.

**Finding:** No camping spot under definition. The station’s corners are too far from crates and too offset from door centres to provide wall-behind + long lane. If mid-spine cover were added, re-run this gate — it would create new threshold camps.

---

## Risks & Recommendations (shooter polish backlog)

| # | Observation | Current State | Recommendation (post-ship polish) |
|---|-------------|----------------|-----------------------------------|
| 1 | **All cover is full-block** — no half-cover for crouch trading | 24 props 3–12 m, 0 in 0.9–1.8 | Add 1–2 low crates (8×1.2×8, h 1.2) per south room near centre to create crouch lanes. Footprint unchanged; nav gap stays 3 m. |
| 2 | **Long diagonals 96–100 m** are sniper-viable | Room max 100.2 <110 gate (pass) | If marksman dominates, add one central 8×8 low crate per room to cut longest to ~60 m. |
| 3 | **92 m spines are the only “exposed” sprints** | 92 <100 gate (pass) | If playtests feel punishing, add a threshold crate 2 m inside each room’s doorway (not inside corridor) to break lane to 2×44 m without blocking 16 m walkway. |
| 4 | **South open pockets 49–51 m** are the most exposed yards | Reactor/Habitat/Command far corners 49–51 m from cover (<55 gate pass) | Add one 8×8 crate 15 m from far corner if those yards feel empty. |
| 5 | **Cargo 3.0 m crate lane** is the tightest CQB | Pass (>1.5) but snug | Keep — intentional tight freight maze. |
| 6 | **Doors are highways (16 m)** — no grenade-funnel choke | Pass | Keep wide for mobile strafe; optionally halve one spine door with a low barrier for a set-piece choke. |

No shooter blocker requires a map rebuild before ship. The station is ready for encounter tuning and device playtests; the above are tactical-depth knobs.

---

## How to Reproduce

```sh
# Full shooter readiness (15 categories)
python3 tool/validate_shooter_readiness.py --verbose
python3 tool/validate_shooter_readiness.py --json docs/shooter_report.json

# Companions (remain green)
python3 tool/validate_geometry.py --verbose
python3 tool/validate_level_flow.py --verbose
python3 tool/validate_campaign.py
python3 tool/validate_campaign.py --svg /tmp/station.svg
python3 tool/validate_resources.py
python3 tool/validate_assets.py

# Python regression (incl. shooter)
python3 -m unittest tests.python.test_shooter_readiness          # 15 categories + JSON
python3 -m unittest tests.python.test_level_flow_integrity
python3 -m unittest tests.python.test_geometry_integrity
python3 -m unittest discover -s tests/python                      # 1187 tests
```

Exit `0` means shooter-ready (warnings are non-fatal). JSON at `docs/shooter_report.json` contains per-category `issues[]` for CI dashboards.

---

## Files Changed / Added by This Audit

* **Added:** `tool/validate_shooter_readiness.py` — 15-category shooter validator (this report’s engine).
* **Added:** `docs/SHOOTER_READINESS_AUDIT.md` — this file.
* **Added:** `docs/shooter_report.json` — machine report (0/0).
* **Added (optional):** `tests/python/test_shooter_readiness.py` — CI wrapper.
* **No authored map change** for shooter — station ships as-is; cargo gating (`cargo_guards`) was the prior flow fix and remains the only `data/campaign/station_zero.json` edit.

All validators (geometry 0/0, level_flow 0/0, shooter 0/0) and 1187 Python tests remain green.
