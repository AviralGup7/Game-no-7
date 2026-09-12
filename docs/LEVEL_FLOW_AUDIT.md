# Level Layout & Spatial Flow Audit — Agent 2

**Date:** 2026-09-12 (re-run against the restored twelve-district station)
**Auditor:** Agent 2 — Level Layout & Spatial Flow
**Scope:** Continuous campaign world `data/campaign/station_zero.json` — 864 × 672 m authored bounds, 12 districts, 47 floor regions, 35 decks — decomposed into corridors → rooms → combat sections → transitions, plus the authored campaign path (`missions` / `encounters` / `interactions` / `sectors` / `floors`)
**Tool:** `tool/validate_level_flow.py` (stdlib only, no Godot runtime) + `tool/validate_geometry.py` + `tool/validate_campaign.py` + `tool/validate_resources.py` + runtime parity checks against `scripts/campaign/CampaignGeometry`, `scripts/campaign/CampaignWorld`, `scripts/arena/ArenaNavGrid`
**Result:** **PASS — 0 errors, 0 unacknowledged warnings** across 10 spatial-flow categories, with **2 acknowledged design notes** (both in `campaign_path`, both carrying a written rationale that CI re-verifies). Navigation, corridors, doors, dead ends, blocked passages, connectivity, isolation and campaign path are sound.

---

## Executive Summary

Station Zero is a single-level, flat (`y = 0`) **864 × 672 m** station built as a **4 × 3 district mesh stitched by 35 decks**: twelve identical `128 × 112` districts, seventeen `48 × 16` / `16 × 48` connectors (each the *only* route between exactly two districts), fourteen spurs (eight `16 × 72` ring spurs + six `40 × 16` side spurs, each leading to exactly one district) and four long perimeter spines that form a **2 688 m service ring** around the outside.

Every one of the 35 decks is fully walkable at its authored width, every door/entrance is snapped to the 8 m module grid and walkable on both sides of the shared edge, there are **zero dead-end nav cells**, **zero blocked corridors**, **zero pinched doorways** and a single walkable island of **13 440 cells** (216 × 168 = 36 288 nav cells; 215 040 m² walkable ≈ 37 % of the grid). Every checkpoint / objective / spawn / prop sits on the walkable mesh and is reachable from the Docks start via the `CELL = 4 m` + `CLEARANCE = 2.5 m` conservative nav mask used by both the validator and `ArenaNavGrid.build_world()`.

The authored campaign path visits **all twelve districts in a single pass** and returns to the Docks only for the scripted extraction:

`docks(arrival) → transit → hydroponics → foundry → cargo → reactor → medbay → habitat → salvage → archive → comms → command → docks(home)`

13 missions, ≈ **4 260 m** of nav-mesh travel against a **6 048 m** budget (7 × the authored width), longest single leg **544 m** (`forge_passage → cargo_records`) against a **1 095 m** straight-line-diagonal budget, and no district re-entered before the finale. Rewards escalate monotonically (`credits 100 → 800`, `xp 60 → 600`).

```
$ python3 tool/validate_level_flow.py --verbose
Level flow: 2 issue(s) — 0 error(s), 0 unacknowledged warning(s), 2 acknowledged design note(s)

$ python3 tool/validate_geometry.py --verbose
Geometry integrity: OK — 0 issues (0 errors, 0 warnings) across 13 categories

$ python3 tool/validate_campaign.py
Campaign topology/content: OK {"districts":12, ... "reachable_walkable_cells":13440}
```

Geometry (Agent 1) remains green — this audit subsumes flow concerns without overlapping its solid-vs-visual, floating, or resource gates.

---

## Derived topology (no hardcoded station shape)

`tool/validate_level_flow.py` never hardcodes the station's shape. Every count and threshold is derived from the authored data at run time:

| Term | Derivation | Current value |
|------|-----------|---------------|
| **district** | a `floors` rect that equals a `sectors[].rect` | 12 (`128 × 112`) |
| **deck** | any other `floors` rect | 35 |
| **connector** | a deck that touches exactly 2 districts on parallel walls | 17 (`48 × 16` / `16 × 48`) |
| **spur** | a deck that touches exactly 1 district | 14 (8 ring `16 × 72`, 6 side `40 × 16`) |
| **spine** | a deck that touches no district and ≥ 2 other decks | 4 (2 × `736 × 16`, 2 × `16 × 608`) |
| district degree budget | `len(sectors) > 2 → ≥ 2 decks each, ≤ len(sectors)` | 2 … 12 |
| traversal budget | `7 × authored width` (and `≤ 2 × walkable area / 16`) | 6 048 m |
| per-leg budget | authored diagonal (`dist((minX,minZ),(maxX,maxZ))`) | 1 095 m |
| articulation connectors | bridge edges of the derived district adjacency graph | 17 (all of them) |

Because the model is derived, the same gate accepts the earlier six-district layout and the current twelve-district one without editing a threshold — the gate fails when the *topology class* breaks (a sealed door, a single-entrance district, a dangling deck, an unsnapped edge, a backtracking mission), not when the station gets bigger.

---

## Methodology

Offline, deterministic, engine-free, **contract-parity** with runtime:

* **Floor union:** `MODULE = 8.0` cells (as `CampaignGeometry.floor_cells`), nav mask `CELL = 4.0` + `CLEARANCE = 2.5 m` inflation around every solid `footprint(at ± size/2)`. A cell is walkable iff its **center** lies inside a `floors` rect and outside every inflated prop. Identical to `validate_campaign.Topology` and `CampaignWorld.nav.build_world`.
* **Walkability & flow:** 4-way BFS from the Docks checkpoint `[-216, 0.2, 44]`. Reachability tested against both the BFS reachable set and the `ArenaNavGrid` diagonal-corner-cut rule. 216 × 168 = 36 288 total cells, 3 768 floor modules, 13 440 walkable, 1 676 perimeter edges.
* **Deck classification:** `rects_touch` (exact edge coincidence ±1e-6) yields the district adjacency graph and each deck's role. A district's door line is derived from which wall the deck touches (`door_lines`), never from a hardcoded orientation.
* **Door lanes:** 7 sample points across each opening (1 m inset from both jambs) and 5 rows deep on both sides (1, 2, 4, 6, 8 m), each a full `walkable_lane` probe — so a prop parked *just inside* a doorway is caught even when the door's centre line stays clear.
* **Width sampling:** deck interiors sampled per row/col; widths must be whole multiples of the 8 m module and ≥ 16 m.
* **Path lengths:** BFS with 4 m steps, distance summed via `math.dist` over cell centers; district-to-district hop distance via BFS over the derived adjacency graph (`MAX_PATH_HOPS = 3` links between consecutive missions).

No art sampled; all checks are coordinate / topology.

---

## Category Results

### 1 — Intended Structure (`structure`)

**Rule:** every `sectors[].rect` must have a matching floor (no room opening onto void); every deck must be at least `MIN_DECK_WIDTH = 16 m` (two 8 m modules) and snapped to the module grid; every deck must *lead somewhere* — two districts (a causeway), one district plus the deck network (a spur), or no district plus >= 2 decks (a perimeter spine); no deck may touch more than two districts (a fan seals the routes it opened); every district keeps >= 2 decks (no single-entrance dead-end room); every district hosts >= 1 encounter (error) and >= 1 interaction (warning).

**Result:** ✔ 12 districts of `128 × 112` (14 336 m² each), 35 decks in the three canonical shapes, district degrees 2 - 4 (hydroponics / foundry / salvage / comms 2; docks / transit / cargo / medbay / archive / command 3; reactor / habitat 4), 32 encounters and 30 interactions distributed 2 - 4 per district, no fan, no dangling deck, no dead-end room.

### 2 — Player Navigation (`navigation`)

**Rule:** `reachable == walkable` from the Docks checkpoint, and every checkpoint, interaction and encounter spawn must sit on a walkable cell that is in the reachable set — not islanded, not inside an inflated prop footprint.

**Result:** ✔ `walkable 13440, reachable 13440` from `[-216, 0.2, 44]` — a single island. 12 checkpoints, 30 interactions and 96 authored spawns all on clear, reachable cells. (Props themselves are covered by Agent 1's `validate_geometry.py`, which additionally proves every objective and spawn reachable and every checkpoint clear.)

### 3 — Dead Ends (`dead_ends`)

**Result:** ✔ 0 degree-1 nav cells, 0 dead-end districts — no pocket traps the player or an escort, and every district has a way out that is not the way in.

### 4 — Blocked Corridors (`blocked_corridors`)

**Rule:** every deck must keep a fully walkable interior band — every row of an east-west deck and every column of a north-south deck.

**Result:** ✔ all 35 decks pass (17 connectors, 14 spurs, 4 spines). Longest deck 736 m (`736 × 16` south spine) is open along its whole length.

### 5 — Narrow Passages (`narrow_passages`)

**Result:** ✔ no inter-prop gap under `MIN_WALKWAY = 2.0 m` (expanded by `AGENT_MARGIN`), and every doorway keeps ≥ 8 m of free lane — the 16 m openings never squeeze to a single-file slot between two props.

### 6 — Door Alignment (`door_alignment`)

**Rule:** each district–deck interface must be 16 m wide on the 8 m module, flush on the shared edge (±0.05), 5 m deep in open floor on both sides, and — via `door_lanes` — must keep **7 walkable lanes across the whole 16 m opening** sampled 1 … 8 m deep on both sides.

**Result:** ✔ all interfaces pass. Twelve authored props (16 × 8 pallets / cranes / vaults) were originally parked 4 m inside a district edge, centred on a 16 m doorway: their 2.5 m inflated footprint blocked the whole nav-cell row across the opening and sealed those doors. Each was moved 8 m deeper into its own district (`hydro_pallet`, `dock_crane`, `transit_crane`, `reactor_pump`, `cargo_pallet`, `habitat_pallet`, `foundry_heat_exchanger`, `medbay_pallet` at `z ± 8`; `salvage_pallet_b`, `command_pallet_b`, `archive_vault`, `comms_pallet_b` at `z − 8`) — still inside the district, still clear of every spawn, checkpoint and objective at 2.5 m inflation, and the walkable-cell count is unchanged at 13 440.

### 7 — Vertical Flow (`vertical`)

**Result:** ✔ n/a by design — the station is single-level (`y = 0`); the rule still asserts every authored `y` is the floor plane so a stray elevated prop cannot appear.

### 8 — Connectivity (`connectivity`)

**Result:** ✔ district adjacency graph connected (4 × 3 mesh + perimeter ring), **no articulation deck** — removing any single one of the 35 decks leaves the whole 13 440-cell island reachable, so no corridor is a single point of failure. 0 isolated districts, 0 unreachable floors.

### 9 — Isolated Areas (`isolated_areas`)

**Result:** ✔ 1 island of 13 440 cells; no orphan geometry, no unreachable void inside the floor union.

### 10 — Campaign Path (`campaign_path`)

**Rule:** the run must end with an extraction back in `docks` (the "long way home" promise), every district is visited at most once (only the finale may return to the opening district), consecutive missions must be within `MAX_PATH_HOPS = 3` district links, every mission target must resolve and be reachable, traversal must stay inside the derived budgets, credit rewards must be monotonic, and a district with guards must gate its objective (`requires`) so combat is not skippable by accident. Guard coupling is checked both ways: a guard inside `GUARD_CLOSE_WARN = 10 m` of its objective is "on the switch", one beyond `GUARD_FAR_NOTE = 45 m` is loosely coupled.

**Result:** ✔ 0 errors, 0 unacknowledged warnings, 2 acknowledged notes.

| Measure | Value | Budget |
|---------|-------|--------|
| districts visited | 12 / 12 | all |
| missions | 13 | — |
| rewards | credits 100 → 800, xp 60 → 600 (monotonic) | increasing |
| total nav traversal | 4 260 m | 6 048 m |
| longest leg | 544 m (`forge_passage` foundry → `cargo_records` cargo, around the ring) | 1 095 m |
| max district hops between missions | 3 | — |
| missions gated on a same-district encounter | 9 / 13 (`restore_transit`, `green_deck`, `forge_passage`, `cargo_records`, `coolant`, `survivors`, `salvage_run`, `send_signal`, `commander`) | — |

---

## Accepted design notes

These warnings are still *computed* every run; they are accepted in `ACKNOWLEDGED_WARNINGS` with a written rationale, and CI fails if the note ever stops matching reality (the glob must match, and an entry without a rationale is a hard error — see `tests/python/test_level_flow_integrity.py`).

| Id | Note | Why it is accepted |
|----|------|--------------------|
| `campaign_path:triage` | medbay has 8 guards but `requires = []` — the medkit consoles are not locked behind the district clear | Medical triage is an authored quiet beat. The wardens patrol 11 m from both medkits, so combat is unavoidable in practice (their `vision_range` is 17 m), but the consoles deliberately do not lock: the player may talk to the survivors mid-fight. |
| `campaign_path:archive_names` | archive has 9 guards but `requires = []` — the three data cores are not locked behind the district clear | Data Archive is the campaign's stealth beat: the cores sit 8 m from the sentries and the mission intentionally does not require clearing them, so a player who slips through the stacks is rewarded. The other nine missions (`restore_transit`, `green_deck`, `forge_passage`, `cargo_records`, `coolant`, `survivors`, `salvage_run`, `send_signal`, `commander`) each lock their objective behind a same-district patrol. |

---

## Reproduction

```bash
python3 tool/validate_level_flow.py --verbose          # human-readable, exits non-zero on any error
python3 tool/validate_level_flow.py --json docs/level_flow_report.json
python3 -m unittest tests.python.test_level_flow_integrity
```

CI wiring: `validate-resources` in `.github/workflows/android.yml` runs the validator directly; `scripts/build_android.sh` re-runs it offline before packaging.

---

## Change log vs the six-district audit

PR #60 introduced this gate against a 352 × 272 m / six-district layout; a merge conflict then silently reverted PR #59's twelve-district expansion, leaving the gate, the tests and this document describing a station that no longer matched the data. Both are now reconciled:

1. **Map restored** to the twelve-district 864 × 672 m station from PR #59, with PR #60's pacing fix preserved (`cargo_records` now requires `cargo_guards`).
2. **Gate generalized** — districts/connectors/spurs/spines are classified from the data; the hardcoded `("command", "reactor")` spawn exemption, the fixed `7`-corridor expectation and the fixed `1160 m` traversal expectation are gone.
3. **Door lanes added** — the twelve doorway-sealing props were found by sampling lanes across the *whole* opening instead of only its centre, and were moved rather than exempted.
4. **Acknowledged-warning model added** — accepted design notes now live in the validator with a rationale, are asserted by the unit test, and fail CI if the note's meaning drifts.

## Polish backlog (non-blocking)

* Give `triage` and `archive_names` authored `requires` entries so the optional-combat warning can be retired — both notes exist only because those two beats are deliberately ungated.
* The 2 688 m service ring carries no authored landmarks; two or three ring-side props would break up the sprint without touching any flow rule (`validate_shooter_readiness` accepts the open ring by design).
