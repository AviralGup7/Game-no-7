# Shooter Gameplay & Combat Readiness Audit — Agent 3

**Date:** 2026-09-12 (re-run against the restored twelve-district station)
**Auditor:** Agent 3 — Shooter Gameplay & Combat Readiness
**Scope:** Continuous campaign world `data/campaign/station_zero.json` (864 × 672 m, 12 districts, 47 floor regions, 72 cover props, 32 encounters / 96 authored spawns, 12 checkpoints) read as a cover shooter, plus the authored combat data it is balanced against (`data/weapons/*.tres`, `data/enemies/*.tres`) and runtime parity with `scripts/arena/ArenaNavGrid`, `scripts/campaign/CampaignWorld`, `scripts/enemies/enemy_base.gd`
**Tool:** `tool/validate_shooter_readiness.py` (stdlib only, no Godot runtime) + `tool/validate_level_flow.py` + `tool/validate_geometry.py` + `tool/validate_campaign.py`
**Result:** **PASS — 0 errors, 0 unacknowledged warnings** across 15 combat-readiness categories, with **1 acknowledged design note** (`service_ring`, rationale below). Every distance the gate uses is derived from the shipped weapons and enemies, not hardcoded.

---

## Executive Summary

Station Zero plays as a cover shooter whose combat distances come from the data: the longest authored weapon reach is **22 m** (`attack_range` across 9 weapons) and the longest enemy sight line is **30 m** (`vision_range`, `warlord_enemy.tres`; ranged enemies fire out to 14 m). Every spatial rule is a multiple of those two numbers, so the gate stays true if the balance ever changes.

* **Cover density is uniform:** all twelve districts are dressed to **8.3 %** prop footprint (inside the 5 %–18 % band) with **6 props each**, giving 1 593 – 2 389 m² per authored enemy — denser than the 2 500 m²/enemy sparse-pacing warning.
* **No unbroken fire lane inside a room:** the longest clear line of sight in any district is **147 m** (corner-to-corner across `128 × 112`), and cover sits **1.7 m** beside that lane — well inside the derived `COVER_REACH = 2 × 22 = 44 m` rule. Nothing approaches the `132 m` warn / `176 m` error room-LOS budgets *without* cover next to it.
* **The only long open run is the perimeter service ring** — four spine decks totalling **2 688 m** with no interior cover (longest cover-free run 736 m). It is acknowledged by design (see below): it closes a loop, is never the only route between two districts, and is patrolled by four ring encounters.
* **Spawns and checkpoints are safe by the derived margins:** every enemy spawn is on a walkable cell with ≥ 2 escape cells, every checkpoint is **40.8 m** from its own district's nearest guard (> `PLAYER_SAFE_MIN = 24 m`), and no spawn is inside a prop.
* **Flanking and loops exist:** every district keeps ≥ 2 deck entries and the district graph carries **6 independent cycles** (17 edges, 12 districts), so no fight is a single-door corridor duel.

```
$ python3 tool/validate_shooter_readiness.py --verbose
Shooter readiness: 1 issue(s) — 0 error(s), 0 unacknowledged warning(s), 1 acknowledged design note(s)
```

---

## Derived combat budgets

`combat_reach()` parses `attack_range` / `vision_range` / `ranged_range` out of the authored `.tres` files at run time; the budgets below are recomputed on every CI run.

| Value | Derivation | Current |
|-------|-----------|---------|
| `ENGAGEMENT_REACH` | max `attack_range` over `data/weapons/*.tres` (9 read) | **22 m** |
| `ENEMY_VISION` | max `vision_range` over `data/enemies/*.tres` (8 read) | **30 m** (warlord) |
| enemy ranged reach | max `ranged_range` | 14 m |
| `COVER_REACH` | `2 × ENGAGEMENT_REACH` — cover must sit within two weapon reaches of an open lane | **44 m** |
| `SIGHTLINE_ROOM_WARN` | `6 × ENGAGEMENT_REACH` | **132 m** |
| `SIGHTLINE_ROOM_ERROR` | `8 × ENGAGEMENT_REACH` | **176 m** |
| `COVER_INTERVAL` | `8 × ENGAGEMENT_REACH` — cover must recur this often on a long run | **176 m** |

Fixed combat-design constants (unchanged, and independent of station size): cover ratio 5 % / 18 % / 35 %, `NO_COVER_DISC_R = 18 m`, `NO_COVER_WARN_DIST = 55 m`, `ENEMY_COVER_FAR_WARN = 90 m`, `PLAYER_SAFE_MIN = 24 m`, `ARENA_AREA_PER_ENEMY_WARN = 2 500 m²`, `CHOKEDOOR_MIN = 3 m`, `PROP_GAP_MIN = 1.5 m`, `CAMP_SIGHT = 65 m`, `CAMP_COVER_DIST = 6 m`; sight lines are raycast at `EYE_H = 1.6 m` against `WALL_H = 1.8 m` props.

---

## Methodology

Offline, deterministic, engine-free, parity with runtime:

* **Nav mask:** `CELL = 4 m` + `CLEARANCE = 2.5 m` inflation around every prop footprint — the same conservative mask `ArenaNavGrid.build_world()` and `CampaignWorld` use, so "walkable" means what the engine means.
* **Line of sight:** sampled segment test in the XZ plane (`has_los` → `seg_intersects_rect`) against every prop footprint and the merged perimeter walls. Every authored prop is 3 – 10 m tall against a 1.6 m eye, so a footprint block is a genuine visual block; category 14 separately proves no prop is low enough to step over.
* **Cover adjacency:** `cover_beside_lane` measures the shortest distance from a sampled LOS lane to any prop rect via `segment_rect_distance`, so a lane is only a problem when nothing sits within `COVER_REACH` of it.
* **Deck roles:** `classify_decks` labels every non-district floor rect as `connector` (2 districts), `spur` (1 district) or `spine` (0 districts, ≥ 2 deck neighbours) — the same classification `validate_level_flow.py` uses, so both gates describe the same station.
* **Spawn patrol exemption:** a spawn that sits outside every district rect is a deck patrol (ring/spur encounter); it is judged against deck rules, not room rules — no district name is special-cased any more.

---

## Category Results

| # | Category | Rule | Result |
|---|----------|------|--------|
| — | reach budgets | weapons/enemies parsed; budgets derived | ✔ weapon 22 m, vision 30 m, room LOS 132 / 176 m, cover interval 176 m |
| 1 | `cover_placement` | 5 % – 18 % prop footprint per district, ≥ 3 props | ✔ 8.3 % and 6 props in all 12 districts |
| 2 | `sightline_problems` | a district lane longer than 132 m (warn) / 176 m (error) is only a defect if no cover lies within 44 m of it | ✔ longest lane 147 m, cover 1.7 m beside it (all 12 districts) |
| 3 | `extremely_long_exposed_corridors` | a connector deck must not run longer than the 176 m cover interval without cover; a perimeter spine that closes a loop is an acknowledged note, any other long open deck is an error | ✔ all 17 connectors well under the interval; 4 spine decks (2 688 m) acknowledged as `service_ring` |
| 4 | `unintended_sniper_sightlines` | no diagonal district lane that reads corner to corner with no cover beside it | ✔ 0 |
| 5 | `areas_with_no_cover` | no open pocket whose centre is > 55 m from the nearest prop (18 m disc test) | ✔ 0 |
| 6 | `areas_with_excessive_cover` | no district above 35 % footprint | ✔ max 8.3 % |
| 7 | `enemy_spawn_feasibility` | every spawn on a walkable cell with ≥ 2 escape cells; deck patrols exempt from room rules | ✔ 96 / 96 |
| 8 | `player_spawn_safety` | every checkpoint ≥ 24 m from a same-district guard | ✔ all 12 at 40.8 m |
| 9 | `arena_combat_space_dimensions` | ≤ 2 500 m² per authored enemy, narrow side ≥ 40 m | ✔ 1 593 – 2 389 m²/enemy, 112 m narrow side |
| 10 | `chokepoints` | no deck narrower than 3 m, no prop gap under 1.5 m | ✔ 0 |
| 11 | `flanking_routes` | every district keeps ≥ 2 deck entries | ✔ 2 – 4 entries |
| 12 | `traversal_loops` | the district graph must carry ≥ 2 independent cycles | ✔ 6 cycles (17 edges / 12 districts) |
| 13 | `navigation_around_props` | props keep ≥ 1.5 m of nav gap | ✔ 0 pinches |
| 14 | `head_height` | every cover prop must be ≥ 0.5 m tall — real cover, not something to step over | ✔ heights 3 – 10 m; the station has no 0.9 – 1.8 m half-cover by design (all full-block industrial crates), which the gate notes but does not warn |
| 15 | `camping_spots` | no corner holding cover that commands a > 65 m lane into a deck | ✔ 0 |

---

## Accepted design notes

Warnings are still computed every run; an accepted one lives in `ACKNOWLEDGED_WARNINGS` with a written rationale, and CI fails if a note ever stops matching reality (the id glob must match and an entry without a rationale is a hard error — `tests/python/test_shooter_readiness.py`).

| Id | Note | Why it is accepted |
|----|------|--------------------|
| `service_ring` | 4 perimeter decks totalling 2 688 m close a loop and carry no interior cover (longest cover-free run 736 m > 176 m) | The outer service ring is an intentionally open perimeter sprint lane. It is never the only route between two districts (`validate_level_flow` proves no articulation deck), four authored ring encounters patrol it, and nothing in the shipped combat data engages beyond 22 m or sees beyond 30 m — an open lane cannot be shot down its length. Cover lives inside the twelve districts the ring connects. |

The note is *earned*, not assumed: the validator only aggregates decks whose role is `spine` (no district, ≥ 2 perimeter neighbours) **and** re-checks that each of them touches ≥ 2 other spines, i.e. that they really close a loop. Any other deck — connector, spur or dangling — that runs cover-free for more than 176 m is reported as an error, so the acknowledgment cannot silently absorb a new death lane.

---

## Risks & recommendations (shooter polish backlog, non-blocking)

* **Ring cover beats.** Two or three low props on the 2 688 m service ring would let a player break a 736 m sprint without changing any gate result; today the ring is deliberately bare.
* **Ungated districts.** `triage` (medbay) and `archive_names` (archive) place their objectives 11.3 m and 8.0 m from the nearest guard and carry no `requires` gate. Shooter-wise that is fine (the guards see 17 – 18 m, so contact is unavoidable), but it is the reason `validate_level_flow` carries two acknowledged notes.
* **Warlord sight.** `ENEMY_VISION` is set by a single boss (`warlord_enemy.tres`, 30 m). If a common enemy ever gains ≥ 30 m sight, the room-LOS budgets stay put but the ring note's rationale ("nothing sees beyond 30 m") must be re-read.

---

## How to reproduce

```bash
# Full shooter readiness (15 categories)
python3 tool/validate_shooter_readiness.py --verbose
python3 tool/validate_shooter_readiness.py --json docs/shooter_report.json

# Companions (remain green)
python3 tool/validate_level_flow.py --verbose
python3 tool/validate_geometry.py --verbose
python3 tool/validate_campaign.py

# Python regression (incl. the derived-budget test)
python3 -m unittest tests.python.test_shooter_readiness
```

CI wiring: `.github/workflows/android.yml` runs this gate through `tests/python/test_shooter_readiness.py` (which fails on any error *or* any unacknowledged warning), and `scripts/build_android.sh` re-runs the companion validators offline before packaging.

---

## Change log vs the six-district audit

1. **Budgets are derived, not hardcoded.** The gate used to assert absolute sightline/cover distances tuned on a 352 × 272 m station. It now reads `attack_range` / `vision_range` / `ranged_range` from the authored `.tres` data and scales every room-LOS, cover-reach and cover-interval rule from the resulting 22 m / 30 m, so the same gate is meaningful on any station size or balance pass.
2. **Cover-conditioned sightlines.** A long lane is a defect only when nothing is within `COVER_REACH` of it; the per-district lane length and its nearest cover are now reported (`sightlines` in the JSON report) instead of a bare length.
3. **Role-aware corridors.** Exposed-corridor and sniper rules classify decks (connector / spur / spine) rather than assuming every long rect is a causeway, and the perimeter ring is aggregated into a single acknowledged note that the validator re-proves is a closed loop.
4. **No special-cased districts.** The old `("command", "reactor")` spawn exemption was replaced by a general rule: a spawn outside every district rect is a deck patrol.
5. **Acknowledged-warning model.** Accepted notes live in the validator with a rationale, are asserted by the unit test, and fail CI when their meaning drifts.
