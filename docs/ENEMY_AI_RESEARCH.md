# Enemy AI Research — How "Perfect" Feels Human

Research pass (2026-09-08) for making the arena's enemies feel like individuals
instead of homing missiles, and for guaranteeing no actor ever walks through an
object. Sources are web game-dev literature + **free, open-source games on
GitHub**, each compared below with what we adopted.

---

## 1. What makes enemy AI feel human (web research)

Consensus across GameDev.net / StackExchange / r/gamedev threads:

1. **Perfect play reads as "not alive".** An enemy that sees through walls,
   reacts on frame one and picks the optimal strategy every time feels like a
   spreadsheet. Small, *plausible* imperfections are what players project
   personhood onto (r/gamedev "How to make enemy AI feel natural";
   gamedev.stackexchange "What makes a computer opponent feel alive?").
2. **Stimulus → reaction → commitment.** Humans need a beat to notice a threat,
   turn toward it, then act. A short, variable reaction delay (plus a visible
   "look" during it) is the single cheapest humanizer.
3. **Imperfect senses.** Limited sight range + field of view + **line of sight
   through geometry**. An enemy that won't sprint at a player it cannot see —
   and that walks *around* the pillar instead of through it — instantly reads
   as a physical being.
4. **Memory and follow-up.** When sight is lost, humans go to where they last
   saw you, check, then lose interest. "Last seen" memory with a forgetting
   timer is the classic investigate behavior.
5. **Noise is a second sense.** Getting hit, hearing an ally hit, or the
   player's weapon noise pull attention without sight. This is also the
   cheapest **pack coordination**: one hit alerts nearby allies.
6. **Cadence, not clocks.** Synchronized swings from N identical enemies is a
   horde tell. Jittered attack cooldowns, staggered engagement and per-individual
   "decision clocks" make a pack fight like a pack.
7. **Personality.** A deterministic per-enemy cast (aggression, caution, aim
   skill, preferred flank) turns archetypes into individuals — and keeps runs
   reproducible (important for this repo's determinism principle).
8. **Grief and self-preservation.** Backing off briefly after nearby allies
   die (when wounded and cautious) makes loss feel meaningful.
9. **Movement vocabulary.** Strafe, flank, circle, pause-and-reassess — chosen
   on a personal timer — beat pure vector pursuit for "alive" by a wide margin.
10. **Imperfect aim with a warning.** Ranged enemies whose first shot is
    looser (a dodgeable warning) and whose spread grows with distance are fair
    and human; lasers from the first frame are not.
11. **The illusion is mostly animation + response, not tactics.** Big-tactic
    AIs are expensive; a "sense-think-act" loop with a short list of readable
    actions beats a solver (same conclusion in the "semi-autonomous perception"
    answers on gamedev.stackexchange).

## 2. Open-source games on GitHub — comparison

| Project (free / OSS) | License / link | Technique | What we took from it |
| --- | --- | --- | --- |
| **Griiimon/Manymies** — https://github.com/Griiimon/Manymies | MIT | Steers **1500+ enemies at 60 FPS** with a **shared, precomputed grid flow field** (`solutions/grid pathfinding/grid_pathfinding.gd`): one BFS/Dijkstra from the player's cell, rebuilt only when the player crosses a cell; every enemy then reads a direction from its own cell. | **Adopted the architecture**: `ArenaNavGrid` builds one flow field per arena, the Arena refreshes it at 10 Hz, and *every* enemy reads `flow_field_direction()` — O(1) per enemy, zero per-enemy path allocation. Per-enemy A* (`find_path`) is kept only for one-off goals (investigation). |
| **godot-demo-projects `2d/navigation`** — https://github.com/godotengine/godot-demo-projects/tree/master/2d/navigation | MIT (Godot) | Reference use of `NavigationRegion2D` + `NavigationAgent2D`: continuous-area routing with `get_next_path_position()` and desired-distance stopping. | Kept the existing `NavigationAgent3D` flat-navmesh path as a **fallback tier** (this repo's 3D arena predates the grid). The demo's "agent does not move the body; the script consumes the path" pattern is exactly how `EnemyNavigator` composes grid → navmesh → direct. |
| **viksl/Godot-Navigation-Agents-Demo** — https://github.com/viksl/Godot-Navigation-Agents-Demo | OSS (Godot 4.5+) | Large agent swarms using the engine's built-in avoidance + multimesh rendering. | Confirms steering-based **separation/avoidance** (soft push between agents) instead of hard body-to-body collision for crowds — we implement the same idea as a cheap 0.12 s sphere query in `EnemyBase._query_separation` (hard collision is reserved for objects, which must *never* be penetrated). |
| **Radialxawn/Godot-Navigation** — https://github.com/Radialxawn/Godot-Navigation | OSS (RVO-style) | Prediction-based avoidance: agents predict next-frame positions and push each other / obstacles out before the overlap happens. | Reinforced the design rule that **avoidance is steering, collision is physics**: the AI intent bends early (flow field + separation), and `move_and_slide()` is the last line of defense, never the plan. |
| **Kid's Code — Godot 4 Recipes: grid pathfinding** — https://kidscancode.org/godot_recipes/4.x/2d/grid_pathfinding/ (+ https://github.com/godotrecipes/grid_pathfinding) | MIT | Canonical 2D **A\* on a uniform grid** with **no corner cutting** (a diagonal move is legal only when both orthogonal neighbors are free). | Adopted verbatim for `ArenaNavGrid.find_path`: 8-neighbor A*, octile heuristic, corner-cut guard, deterministic neighbor order (this repo's reproducibility rule). |
| General literature (flow fields / HMMs / steering) — e.g. Red Blob Games "Flow Fields", "Steering Behaviors" (Cruise) | MIT/CC | Flow fields for multi-agent-to-single-target; steering primitives (seek/flee/separation) for local behavior. | The split this project uses: **global intent = flow field** (Manymies), **local polish = steering** (separation, flanking orbits, strafe). |

Why not just the engine's navmesh (runtime bake) or RVO for everything?
Mobile + determinism: this repo's principle is *deterministic, precomputed,
headless-testable*. A 48×48 shared grid is ~2.3 k cells — one rebuild is a
few thousand heap ops and only happens when the player crosses a cell; every
enemy's per-frame cost is one array lookup. Runtime 3D navmesh baking would
cost memory, be nondeterministic, and still need the grid for LOS checks.

## 3. What was implemented (where it lives)

### 3.1 "Nothing walks through objects" — collision + intent, one source of truth

* `scripts/arena/arena_obstacles.gd` — deterministic obstacle layouts per arena
  (pillars/blocks), hand-cleared against each arena's authored hazard layout and spawn
  markers (asserted by `tests/unit/test_nav_grid.gd`).
* `scripts/arena/arena.gd::_spawn_obstacles` — each entry becomes a
  **StaticBody3D on collision layer 1** — the *same* layer the player
  (mask 1) and every enemy (mask 5) already collide with — plus a stone mesh.
* **The central landmark (forge / crystal / obelisk) now has a collision body
  too** (`_add_landmark_collision`) — previously the one object both the hero
  and the horde could walk straight through.
* `scripts/arena/arena_nav_grid.gd` — the same obstacle set is registered on
  the shared nav grid, so the **AI's intent** routes around exactly what
  **physics** blocks the body with. `ArenaNavGrid.build()` inflates obstacles
  by `AGENT_MARGIN` (0.45 m) so medium bodies never hug them.
* `scripts/enemies/enemy_navigator.gd` — resolution order per frame:
  line of sight → direct (fast, human); else **shared flow field** around
  obstacles; else legacy navmesh; else the caller's direct direction
  (physics still catches the worst case). One-off goals (investigating)
  use a cached A\* path.
* `scripts/enemies/enemy_pack.gd` — soft separation steering keeps packs
  from *overlapping each other* (Steering "separation", the
  Manymies/swarm-standard); objects are handled by collision, peers by
  steering. The same module owns pack awareness (hearing, grief, player
  noise) — see below.
* Player side: `CharacterController` already `move_and_slide()`s against layer
  1 — the new obstacles/landmark are on layer 1, so the hero cannot clip
  them either. No code change needed; the guarantee is now *data*-driven.

### 3.2 "It feels like a human" — the brain

* `scripts/enemies/enemy_perception.gd` — pure sense-think-act module:
  * **Sight**: `vision_range` + `vision_fov_degrees` cone + **grid LOS**
    (no seeing through pillars).
  * **Hearing**: `hearing_range` scaled by noise intensity (allies hit,
    allies killed, player projectiles, player skills, being hit yourself).
  * **Reaction beat**: `reaction_time` (scaled by personality) with a
    visible "turn to look" during it (Idle REACTING branch).
  * **Memory**: `memory_time` of pursuit toward `last_seen_pos` after sight
    is lost; investigate + linger + forget.
  * **Status machine**: `UNAWARE → REACTING → ENGAGED → INVESTIGATING`.
* `scripts/enemies/enemy_personality.gd` — deterministic cast per
  `(run_seed, spawn_serial)` (same RNG stream family as the approach
  offset): aggression, caution, aim skill, strafe bias, reaction scale,
  wander scale, dash willingness, cooldown spread.
* `scripts/enemies/enemy_chase_state.gd` — maneuver clock (0.9–1.8 s):
  straight / flank-A / flank-B / strafe, personality-weighted; grief
  retreat when wounded + cautious after nearby ally kills.
* `scripts/enemies/enemy_attack_state.gd` — per-swing cooldown jitter
  (0.6×–1.4×, personality-scaled): packs no longer swing on one clock.
* `scripts/enemies/enemy_ranged_state.gd` — **LOS-gated firing** (no blind
  shots; repositions for a clean angle), distance-scaled aim error from
  the personality's aim skill, and a deliberately looser **first shot**.
* `scripts/enemies/enemy_idle_state.gd` — unaware enemies **wander** their
  spawn area with random "look around" pauses (during a glance,
  `attention_boost` extends vision 1.6× — a human glancing across the room
  genuinely sees farther for a moment; this is the safety net that makes
  even corner-camped players eventually noticed); reacting enemies hold the
  beat; investigating enemies pace to the last-seen point.
* `scripts/enemies/enemy_pack.gd` — pack-coordination module (same
  composition pattern as EnemyLocomotion/EnemyStriker): hearing an ally's
  hit as a stimulus, grief retreat (2 kills in 4 s near a wounded, cautious
  enemy → brief back-off), player projectile/skill noise, the separation
  query (cached parameters object, no per-query allocation) and the EventBus
  wiring (`enemy_damaged` / `enemy_killed` / `projectile_fired` /
  `skill_cast`) — all injected, tree-free and headless-testable.
* `scripts/enemies/enemy_base.gd` — wires perception + personality +
  nav grid + pack module (delegation only), pain reveals the attacker.
* `scripts/enemies/enemy_config.gd` + `data/enemies/*.tres` — all knobs are
  data-driven and validated; each of the 8 archetypes is tuned (the Warlord
  sees the whole arena and reacts in 0.08 s; the vision floor keeps every
  archetype at 17 m+ so the farthest 15.5 m spawn can never stall unnoticed).
  `detect_range > 0` still overrides `vision_range` (legacy compatibility).

### 3.3 Tests

* `tests/unit/test_nav_grid.gd` — grid build/bounds, LOS through/over a
  wall, flow-field detour + idempotent rebuild, A\* detour + reachability,
  cross-instance **determinism**, and obstacle-layout safety (arena bounds,
  spawn clearance with jitter, hazard clearance, passable gate, scaling).
* `tests/unit/test_enemy_brain.gd` — personality determinism + ranges;
  perception sight cycle, hearing wake + reaction cut, LOS gate, FOV cone,
  memory/investigation, spot-while-investigating, legacy always-aware.
* `tests/run_tests.gd` — new integration check: a perceived stimulus delays
  engagement by the reaction time (the step-counted legacy assertions keep
  exact frame budgets by zeroing `reaction_time` in the probe config).

## 4. What we deliberately did NOT do

* **No neural nets / ML**: overkill for an arena brawler, opaque, and
  non-deterministic — against this repo's reproducibility principle.
* **No behavior trees / utility AI**: the FSM already covers the 8 states;
  the human-feel comes from *senses + noise + personality*, which compose
  with the existing machine (states still only talk through the host's
  command surface).
* **No enemy↔enemy hard collision**: with 12–40 concurrent bodies, mutual
  hard collision causes funneling/jitter in 3D; steering separation is the
  swarm-standard compromise (see the GitHub comparisons above).
* **No hazard pathing**: the design (per `ArenaHazards`) treats kiting
  enemies through vents as a *player* strategy — so the AI does not
  auto-dodge hazards; only geometry blocks intent.

## 5. Robustness hardening (NaN / re-entrancy)

A follow-up hardening pass (previously `docs/ENEMY_AI_ROBUSTNESS_RESEARCH.md`,
merged here) closed the failure modes of the three high-frequency AI modules:

- **`EnemyStateMachine`** no longer changes state while `enter()`/`exit()` or
  `state_changed` listeners request another transition: re-entrant requests are
  serialized (one active state at a time; queued follow-ups drain only after the
  current hook completes). Forced transitions (hurt/dead) supersede a normal queued
  transition; competing normal requests are diagnosed and rejected.
- **`EnemyPerception`** rejects NaN/infinity configuration, frame deltas, positions,
  intensities and memory durations, and resets safely on invalid target/spatial
  input — a poisoned reaction timer or investigation point can no longer lock an
  enemy or leak into navigation.
- **`EnemyNavigator`** validates every vector and substitutes a safe refresh
  interval; invalid inputs return a zero/fallback direction instead of propagating
  NaN into `CharacterBody` velocity.
- Valid-input behaviour (LOS, FOV, flow-field, A*, legacy fallback) is unchanged.

Pinned by `tests/python/test_regress_enemy_ai_hardening.py`.
