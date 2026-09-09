# Changelog

## [Unreleased] — Hero character fidelity (2026-09-09)

- Replace the live KayKit hero mesh with the project-authored **Arena Warden**:
  human proportions, layered armor, mail, gloves, split blue tabard, 1K PBR maps;
  34,860 triangles / 23 deform bones / one opaque body surface.
- Bake all **76 CC0 donor clips** to the new rig, preserving every combat/cast
  selection and hand socket. Condition gait lift, remove planar root travel,
  ground support and preserve pose reset channels. No gameplay/balance changes.
- Add an authored PBR gladius sharing the hero atlas; preserve authored material
  factors, remove the hero float tween and correct left/right dodge selection.
- Gate imports by the full clip/socket contract; keep the complete KayKit rig and
  primitive as fallbacks. Idle autoplay now uses private animation resources.
- Add reproducible authoring/provenance, strict offline validation, 19 focused
  Python tests, native pose/fallback/material tests and a real Player animation
  lifecycle CI gate with isolated saves.
- Add an interactive before/after clip viewer using actual GLBs/HDRIs; restore
  the existing three.js viewer's missing core dependency.
- Validation scope: both new models pass Khronos with no errors/warnings, focused
  tests and changed-script lint pass, output rebuilds are byte-identical. The full
  Python suite passes 415/415 after incorporating the subsequent fixes from
  `main`. Native Godot CI and device review remain required (the engine is
  unavailable locally).
- This is authored PBR armored art, not a photoreal scanned human or a replacement
  of the entire enemy roster. See `docs/HERO_FIDELITY.md` for remaining limits.

## [Unreleased] — Prestige gets teeth: cosmetics, tiers, objectives (2026-09-09)

Prestige, cosmetics, and challenge tiers were tables of IDs that never touched a
run. This pass makes all three change play.

### Challenge tiers scale the run

`Prestige.CHALLENGE_TIERS` now carries `currency_mult` and `waves` per tier plus
typed accessors (`challenge_tier_label/score_mult/currency_mult/mutator_count/
waves`). `GameMode` reads the player's prestige tier for the Challenge mode via a
new prestige-aware API (`scales_with_prestige`, `challenge_mutators`,
`score_multiplier_for`, `currency_multiplier_for`, `max_waves_for`,
`is_victory_wave_for`). The Challenge run's mutator SET is drawn by tier count
from `CHALLENGE_MUTATOR_POOL` (tier 0 reproduces the historical
`glass_cannon + ember_winds` pair), and its score/currency payout and wave cap
grow with rank — Hard → Nightmare → Mythic → Last Stand are now genuinely harder,
better-paying, longer runs. `WaveManager`, `RunScorekeeper`, `GameRoot`, and the
run-setup preview all consult the tier; the scorekeeper skips the flat per-rank
prestige bonus for Challenge so the tier payout isn't double-counted.

### Cosmetics attach to the world

New `Cosmetics` catalogue turns unlocked cosmetic IDs into applyable definitions
(trail / aura / banner / title, highest rank worn). New `PlayerCosmetics` node
mounts a coloured GPUParticles3D **trail** (ember/frost) and a rotating emissive
**aura** ring + motes on the live hero; `ArenaDecorator.apply_prestige_banners`
hangs unlocked **banners** on the arena walls in their colours; the run summary
shows the prestige title + worn cosmetics. Main reads the persisted unlock list
from `SaveManager` on every run build.

### Objectives become real modes

`OBJECTIVE_DEFEND_POINT` and `OBJECTIVE_COLLECT` (previously constants with zero
implementations) are now the playable modes **Hold the Line** and **Relic Hunt**,
driven by a new per-run `ObjectiveDirector`:
* Hold the Line — a beacon at the arena centre drains while enemies stand in its
  radius and self-repairs when clear; win on the mode timer, lose the instant it
  falls.
* Relic Hunt — slain foes drop `relic_shard` pickups on a deterministic cadence;
  bank the quota to win.
Both have endless spawn queues, HUD progress (`EventBus.objective_progress`), and
resolve through `EventBus.objective_resolved` → GameRoot victory/game-over. Adds
`RunState.objective_progress/objective_failed`, HUD objective line, Narrator
intros, and the `relic_shard` pickup (catalogued; `drop_weight 0` so it never
leaks into normal drop tables).

## [Unreleased] — Smaller product-debt cleanup (2026-09-09)

Follow-up on the remaining QA_RELEASE_AUDIT debt items that were not part of any
feature pass: fail-loud content loading, deletion of the legacy melee path, an
unbiased wave-director count nudge, and a strict (allowlist-free) UI gate.

### Content loading now halts on broken content (debug/test)

`ContentRegistry._ready()` already reported validation problems but then kept
running, so a corrupt `.tres` under `res://data/` could silently ship a game
missing enemies/weapons/upgrades. It now halts in debug/test builds (push_error
+ assert) and still reports every problem in release builds before continuing
with the degraded-but-usable tables. Cleaned up alongside: the write-only
`_validation_dirty` flag and the unreachable duplicate-id loop in `validate_all()`
(ContentLoader rejects duplicate ids at load time) were deleted; both startup and
`validate_all()` now share one error-reporting path.

### Legacy `AttackController`/`ComboChain` removed (M3 cleanup)

`Player._try_attack()` has used the `WeaponManager → WeaponInstance →
MeleeResolver/RangedResolver` path as its single authority since the typed
architecture overhaul; the `AttackController` fallback only ever ran when no
`WeaponInstance` was equipped, which production scenes never hit. Both files are
deleted, the `player.tscn` node and its `ext_resource` are gone, and `player.gd`
no longer resolves/ticks/resets the legacy controller; the vestigial
`Player.attack_hit` signal + handler (never emitted by the weapon path) and
`build_effects.gd`'s legacy wiring to it were removed too. Comments in
`combat_query.gd`, `character_controller.gd`, `player_animation.gd`,
`melee_resolver.gd`, `weapon_manager.gd` and the UI player double were updated;
docs (`ARCHITECTURE`, `EXTENDING`, plus RESOLVED markers on the audit summaries)
now describe `WeaponManager` as the single attack authority. The GDScript
integration suites that drove the legacy class directly were removed/updated
(`run_tests.gd` combo stage, `test_player.gd` legacy-recovery scenario), and the
Python regression guards that read the deleted files were retargeted to the
canonical combat code or inverted into “must stay deleted” guards.

### Wave-director count nudge no longer skews spawn composition

`WaveManager._apply_director_count_nudge` appended `queue[i % queue.size()]`
while the queue grew (sampling from the head) and used `pop_back()` to trim
(dropping the tail). Because spawn queues order weak-to-strong, that over-copied
the weakest front entries and silently deleted late elites/bosses on a down
nudge. The logic is now a pure, headless-testable
`WaveManager.apply_count_nudge(queue, bonus)` that spreads additions/removals
evenly across the ORIGINAL queue. New unit coverage in `tests/unit/test_waves.gd`
(boss preserved on −1, late entries kept on −2, deterministic, never empties a
non-empty plan) plus a structural guard in
`tests/python/test_regress_wave_systems.py`.

### UI validation gate is strict again (allowlist deleted)

The `KNOWN_FAILURES` filter in `scripts/ui/run_ui_validation.sh` masked two
pre-existing runtime bugs surfaced by the UI suite: `RunScorekeeper` calling the
nonexistent `CombatLog.log()` (fixed on `main` — the API is `record`, which the
scorekeeper has used since the runtime-verification pass) and the UI player
double exposing a Dictionary where a typed `ProgressionComponent` is expected
(the double now builds a real `Player` with real typed components). Both
underlying bugs are fixed in this tree, so the allowlist and its rationale
comment were deleted: any `SCRIPT ERROR` / `Parse Error` / `UI FAIL` now fails
the gate again. The suite re-runs in CI (fresh + existing save profiles) to
confirm no masked errors remain.

## [Unreleased] — Recheck, modularize, perfect (2026-09-09)

Follow-up pass over the 2026-09-08 AI/collision work: full re-read of every
touched file, extraction of the last inlined brain logic into the module
pattern, and small correctness/perf fixes.

### New: pack-coordination module (`scripts/enemies/enemy_pack.gd`)

`EnemyPack` (RefCounted, same pattern as EnemyLocomotion/EnemyNavigator/
EnemyStriker) now owns everything "the pack around me": hearing an ally's hit
(stimulus into EnemyPerception), grief-retreat after nearby ally kills,
player projectile/skill noise, and the separation steering query — including
the EventBus wiring (injected `connect_signals`/`disconnect_signals`, so the
module stays tree-free and headless-testable). `EnemyBase` shrank
accordingly and delegates: `is_fear_retreating()`, per-frame `update`/
`apply_separation`, `get_run_time()` for the grief window. Behavior is
unchanged; the query parameters object is now allocated ONCE per enemy
instead of per query (12–40 concurrent enemies was churning GC every
0.12 s).

### Fixes & polish

* **Attention-boost leak** — `enemy_idle_state.gd` reset
  `attention_boost = 1.0` only in the wander branch, so a look-pause boost
  (×1.6) leaked into REACTING/INVESTIGATING for the whole investigate
  window. The baseline is now reset at the top of `physics_update`, before
  any branch; only an ACTIVE look-pause widens sight.
* **Obstacle node building extracted** — `ArenaObstacles.build_nodes()`
  (static, deterministic, no autoload access) creates the StaticBody3D/
  BoxShape3D/BoxMesh set; `arena.gd`'s `_spawn_obstacles` now only resolves
  the parent node and delegates.
* **Flow-field refresh gated** — `arena.gd` skips the 10 Hz flow-field
  refresh entirely while no enemies are on the field (the field rebuilds on
  the first tick of the next wave).
* **Nav margin = capsule radius** — `ArenaNavGrid.AGENT_MARGIN` 0.45 → 0.5
  (the enemy capsule radius) so the path centerline never steers a body's
  edge into a wall. Verified: blocked cells are identical at 0.5 m cell size,
  so existing nav-grid assertions are unaffected.

### Audio content: recorded boss / calm / victory beds

* Previously only the menu and combat loops shipped as recorded audio; the
  boss, calm and victory beds shared the combat loop or fell back to
  procedural pads. All five music states now ship distinct CC0 loops:
  `arena_calm.ogg` (RandomMind — King's Feast), `arena_victory.ogg`
  (RandomMind — Rejoicing) and `arena_boss.ogg` (Juhani Junkala / SubspaceAudio —
  Evil3: Apocalypse), added to `assets/catalog.json` + `assets/manifest.json`
  with checksum-locked provenance and a saved creator notice
  (`ASSET_LICENSES/jrpg-evil.txt`). `AudioAssetIntegrator` now maps each music
  state to its own bed instead of sharing the combat track; the combat loop
  (`arena_gameplay.ogg`) is unchanged.

### Tests

* `tests/unit/test_arena_obstacles_node.gd` (new, NODE_SUITES) —
  instantiates the REAL arena scene headless and asserts end to end: one
  StaticBody3D per layout entry on collision layer 1 with box shape + mesh
  matching the layout, landmark collision body present, wall/floor geometry
  and boundary collision intact, nav grid blocking every obstacle + landmark
  footprint while the gate gap and player start stay walkable, LOS through
  the landmark blocked, flow field steering. The arena is freed before the
  later integration stages run.
* `tests/unit/test_nav_grid.gd` — margin comment updated to 0.5.

## [Unreleased] — Human-like enemy AI + nothing walks through objects (2026-09-08)

Research-driven pass over the enemy brain and arena collision. Full source
analysis (web game-dev literature + free open-source games on GitHub) lives in
`docs/ENEMY_AI_RESEARCH.md`.

### New: shared navigation grid (`scripts/arena/arena_nav_grid.gd`)

One deterministic 48×48 grid per arena (the Manymies flow-field pattern): a
shared flow field toward the player — rebuilt only when the player crosses a
cell — plus per-goal A\* with string-pulling, sampled line-of-sight, no corner
cutting, and deterministic tie-breaks. Pure RefCounted, headless-testable.

### New: interior obstacles the player AND enemies collide with
(`scripts/arena/arena_obstacles.gd`, `scripts/arena/arena.gd`)

Each arena now has a deterministic pillar/block set (hand-cleared against
hazards and spawn markers). Every obstacle is a StaticBody3D on collision
layer 1 — the same layer the player (mask 1) and enemies (mask 5) use — and
the same set feeds the nav grid, so **the AI's intent routes around exactly
what physics blocks**. The central landmark (forge/crystal/obelisk) also gets
a collision body: it was previously the one object both sides could walk
through. Enemy packs also get soft separation steering so they fan out
instead of overlapping each other.

### New: perception + personality (the "human" pass)

* `scripts/enemies/enemy_perception.gd` — sight (range + FOV cone + grid
  line of sight), hearing (ally hits, kills, player attacks/skills, being hit),
  a visible reaction beat, last-seen memory → investigate → forget, and the
  legacy always-aware mode when ranges are zeroed.
* `scripts/enemies/enemy_personality.gd` — deterministic per-enemy cast
  (aggression, caution, aim skill, strafe bias, reaction scale, dash
  willingness, cooldown spread) from `(run_seed, spawn_serial)`.
* Idle now wanders + "looks around" instead of freezing; chase re-rolls a
  maneuver (straight/flank/strafe) on a personal 0.9–1.8 s clock; melee
  cooldowns are jittered per swing (0.6×–1.4×); ranged enemies fire only
  with line of sight, aim with distance-scaled error, and their first shot
  is deliberately loose; wounded cautious enemies back off briefly after
  nearby allies die; dashers sometimes fake a charge by not dashing.
* All knobs are data-driven: 9 new validated `EnemyConfig` fields, tuned
  per archetype in `data/enemies/*.tres` (`detect_range > 0` still wins).
* `scripts/enemies/enemy_navigator.gd` — grid (LOS → flow field → A\*) first,
  legacy navmesh fallback, then direct.

### Tests

* `tests/unit/test_nav_grid.gd` — LOS, flow-field detour/idempotence, A\*
  detour/reach/determinism, obstacle-layout safety (bounds, spawn/hazard
  clearance, passable gate, scaling).
* `tests/unit/test_enemy_brain.gd` — personality determinism + ranges; full
  perception state machine (sight, hearing, LOS, FOV, memory, legacy mode).
* `tests/run_tests.gd` — new "reaction beat" integration check; the
  step-counted encounter assertions keep their frame budgets via
  `reaction_time = 0` in the probe config.

### Notes

* Enemy vs enemy is steering-separated (swarm-standard); enemy vs object and
  player vs object remain hard physics.
* Hazards intentionally stay walkable for the AI (kiting enemies through
  vents remains a player strategy).

## [Unreleased] — Typed architecture overhaul (2026-09-09)

Ends the duck-typing architecture: every component interaction is now a typed,
direct method call. **~10,000 lines rewritten across Player, EnemyBase,
GameRoot, all systems and every UI panel.**

### Removed
- **All 168 `_validated_*`/`_guarded_*` "validation theater" helpers** (141
  were provably dead — defined, never called). The guards that were real are
  inlined at their use sites; `docs/HARDENING.md` is marked SUPERSEDED.
- **All duck typing in `scripts/`**: 308 `.call("...")` sites and 297
  `has_method()` probes are gone (one sanctioned `has_method` assertion
  remains in `test_harness.gd`, where probing IS the job). Dead branches
  exposed by removed probes were deleted (GameRoot armory/arena-selection
  probes that never existed, projectile `set_team_tint`, chase-state dead
  clause, content-loader untyped registration).
- **`run is Dictionary` probing everywhere** — `GameRoot.get_run()` is typed
  (`RunState`); consumers read fields directly.
- 5 pure-theater python test files; ~130 theater assertions stripped from the
  rest (now pinned to real guards instead).

### Added
- `tool/check_typed_arch.py` — architecture gate: bans `.call("...")` string
  dispatch and `has_method(` (allowlisted exception), verifies `as T` casts
  and `Class.member()` calls resolve against declared `class_name`s +
  extends chains (133 classes, 8 autoloads).
- `scripts/core/validated_config.gd` — `ValidatedConfig` protocol base;
  all content configs extend it and ContentLoader runs their `validate()`.
- `class_name RingFade`; `HitstopManager`/`PerformanceMonitor`/`CameraRig`/
  `CharacterController` typed casts in feedback/UI code.
- Real `@export_range` editor enforcement on every authored content config
  (replacing the `pass`-stub `_export_range_guard` documentation theater).
- `docs/ARCHITECTURE.md` — the typed component model, autoload policy,
  seams, and the enforcement gates.
- Typed component accessors on Player (`get_health_component()`,
  `get_weapon_manager()`, `get_skill_controller()`, …).

### Changed
- `UiCommands.action` is a closed typed dispatch (unknown command → warn +
  false); TouchControls/SkillBar route through it.
- `weapon_manager`/`attack_controller`/`skill_controller`/`dodge_controller`/
  `stamina_component` resolve ProgressionComponent/StatusManager as typed
  refs; status effects source from `EnemyBase.get_archetype_id()`.
- SpawnManager's boss path is fully typed (`as BossController`, connect
  `summon_requested` **before** `begin_fight`); arena/placer APIs take
  `Arena` types; fake_arena test double now `extends Arena`.
- `audio_manager` volume/pitch clamps inlined at the voice-claim site;
  `event_bus` dead `_safe_emit`/`_guarded_*` wrappers removed.
- `tool/validate_guards.py` rewritten: pins the real inlined guards +
  @export_range contracts + theater-stays-dead (was: asserted 139/139
  helpers exist).

### Verified
- `gdparse` over all scripts + tests; `gdlint` clean on changed files.
- `tool/check_typed_arch.py`: clean. `tool/validate_guards.py`: exit 0.
- `python3 -m unittest discover tests/python`: 353 tests, all passing.

## [Unreleased] — Gameplay loop overhaul (2026-09-08)

Structural content/design pass that breaks the single-mode grind loop. Code stays
data-driven; modes, transforms, narrative and prestige are additive systems.

### Game modes (`scripts/meta/game_mode.gd`)

Five playable modes selectable from Run Setup:

| Mode | Objective | Notes |
|---|---|---|
| **Standard** | Endless waves | Original loop, unchanged defaults |
| **Boss Rush** | Slay 5 Warlords | No filler packs; elite-surge mutator; upgrade every wave |
| **Survival** | Endure 5:00 | Dense packs; time-based victory; score ticks with life |
| **Challenge** | Clear 12 waves | Fixed Gladius + glass/ember mutators; 1.5× score |
| **Campaign** | Clear 15 scripted waves | Authored encounter beats + narrator lore; final dual Warlord |

Victory ends the run cleanly (`RunState.victory`), banks a larger wallet cut, and
shows a distinct summary banner. Retry preserves the mode.

### Transformative upgrades (8 new cards + `BuildEffects`)

Stat sticks remain, but new **transform** rarity cards change how you play:

- **Storm Edge** — melee hits chain lightning
- **Cinder Step / Glacial Step** — dodge leaves fire trail or frost nova
- **Grave Pact** — kills summon temporary ally auras
- **Thorn Mantle** — taking a hit detonates a thorn nova
- **Reaper's Mark** — execute foes below 18% HP
- **Blood Rite** — every 5th kill heals a burst
- **Static Halo** — shocking aura pulses around you

`UpgradeConfig.effect_tags` + `ProgressionComponent` effect tracking +
`scripts/progression/build_effects.gd` runtime owner. Wired by Main on world build.

### Arena differentiation

Hazards now include **pressure plates** (player-triggered enemy blasts) and
**orbiting movers**, with denser per-arena layouts. Mode pressure adds extra
hazards for Boss Rush / Challenge / Survival / Campaign. Arena tags updated.

### Narrative layer (`scripts/meta/narrator.gd`)

Arena lore intros, mode intros, campaign beat sheet (15 scripted lines), enemy
blurbs. Delivered through the existing announcement banner — no new UI chrome.

### Prestige endgame (`scripts/meta/prestige.gd` + Armory UI)

After ~60% armory completion, spend banked coins to prestige: permanent score/
currency multipliers, titles (Unproven → Last Stand), unlockable cosmetics,
challenge-tier ladder. Save schema v5 carries `prestige_rank` + victory/boss
lifetime counters.

### Tests

`tests/unit/test_game_modes.gd` covers mode catalogue, victory conditions, spawn
queues, narrator, prestige gates, effect tracking, RunState summary fields, and
save migration.

---

## [Unreleased] — HD realism pass (2026-09-08)

Presentation overhaul across the arena, sky, lighting, renderer settings and actor
materials. **No gameplay, rig, animation, balance, save or input changes** — the
same scenes, physics, spawns, navigation and HUD contract are preserved.

### Assets (locked, provenance-kept)

- **17 new checksum-locked downloads (+10.58 MiB, 239 files / 45.63 MiB total):
  three Poly Haven CC0 HDRI panoramas** (spruit sunrise, venice sunset, moonless
  golf — via the pinned, MIT-licensed three.js mirror) and **photo PBR sets from
  Godot's Material Testers** (rock, aged brick, marble, wood, aluminium) at the
  already-pinned `godot-demo-projects` revision. The downloader/validator now
  support `.hdr` and `.jpg` with the same hash locks.
- Five new arena materials under `assets/materials/` (rock floor, brick walls,
  marble, wood, metal); `ASSET_LICENSES/` gains the three.js MIT and
  Godot MIT notices.

### Arena map — replaced

- `scenes/arena/arena.tscn` is rebuilt: photo-PBR rock floor, aged-brick walls
  with stone trims + marble cornices, corner towers with marble caps, an
  iron-banded wooden gate, marble dais, boulders and 4 flickering torch sconces
  (`scripts/arena/torch_flicker.gd`, deterministic, 4 omni lights, no shadows).
- Collision, spawn points, pickup points, navigation floor and arena script
  contract are unchanged; `Arena` themes still tint floor/walls by arena.

### Sky, lighting and renderer

- `arena.gd`: per-arena `PanoramaSkyMaterial` (IBL) with procedural fallback,
  exposure/contrast adjustment, tuned fog, glow on emissives; landmarks use the
  photo-rock/marble materials.
- `project.godot`: 2× MSAA, 8× anisotropic filtering, 2048px high-quality PCF
  directional shadows. Mobile renderer retained (SSAO/SSR off on purpose).

### Actor + prop material pass

- `scripts/visuals/hd_materials.gd` (`HdMaterials`) applies anisotropic filtering
  and role-tuned roughness/metallic/specular to every mounted player/enemy model
  (`CharacterVisuals`, `EnemyAnimator`) and every arena prop/decorator. Shallow
  material duplicates; textures, rigs and animations untouched.
- Rig inventory kept deliberately (combat clip coverage — see
  `docs/ASSET_AUDIT.md` "Why not a photoreal rig swap").
## [Unreleased] — Audit follow-ups: roster smoke, minimap robustness, dead facade (2026-09-08)

Follow-up pass over the remaining small-but-real findings in
`docs/QA_RELEASE_AUDIT.md`, plus hardening of the enemy-inheritance work:

- **TestHarness startup smoke now covers all 8 enemy archetypes** (`_enemy_archetypes_ok`,
  `_spawn_resources_ok`, `_kill_and_wave_scoring_configured` iterate a shared
  `ENEMY_ARCHETYPE_IDS` const). They validated only basic/fast/heavy — the exact
  "works for some enemies" blind spot the scene refactor closed on the scene side.
- **`tests/unit/test_enemy_scene_inheritance.gd` upgraded to full-roster goldens**: every
  archetype (not just the five refactored) now pins collision shape, body mesh, material
  colour, nav distances, marker offsets and animator config against shipped values;
  `path_height_tolerance` and the no-BossController-leak check included.
- **Minimap arena lookup is layout-independent** (audit "fragile hardcoded path"):
  `Arena` joins the `arena` group in `_ready`; `minimap._find_arena()` resolves through
  `get_first_node_in_group` first and keeps the legacy `WorldRoot/Arena` path only as a
  fallback. No behaviour change in main.tscn; the lookup now also survives renames and
  hosts other than the current scene.
- **GameRoot dead facade deleted** (audit "two sources of truth for best score/wave"):
  zero-caller `get_best_score()`/`get_best_wave()` accessors removed; SaveManager remains
  the single public read path (as pinned by the startup-stability guards) and GameRoot's
  `_best_*` mirrors stay internal (run_ended fan-out + debug snapshot only).
- **`tool/validate_resources.py` gained a file-local `SubResource` guard**: scenes that
  `instance=` another scene must not reference the parent's sub-resource ids (the classic
  hand-edit mistake on child scenes like the enemy archetypes); the editor's `[editable]`
  cross-file pointer remains sanctioned. Behaviour-tested in
  `test_regress_tooling_and_ci.py`; verified to flag and to clear real scenes.
- **`audio_config.gd` comment fixed** (audit known-issue #4): AudioConfig instances live in
  `res://data/audio/`; the referenced `res://data/audio_config/` directory does not exist.

## [Unreleased] — Enemy scene inheritance overhaul (2026-09-08)

Closes the audit's "highest-value structural cleanup left": **5 of 8 enemy archetype
scenes were hand-copied full trees** of `enemy_base.tscn`, so any edit to the base
(collision layers, shared child wiring) silently missed dasher/exploder/ranged/
splitter/warlord — the exact mechanism behind audit bug P6-style "works for some
enemies" divergence.

- `dasher/exploder/ranged/splitter/warlord_enemy.tscn` are now true **child scenes** that
  `instance=ExtResource("…/enemy_base.tscn")` and override only their archetype-specific
  bits (collision shape/mesh/material, marker offsets, warlord nav distances) plus their
  unique nodes (`EnemyAnimator` on all five, `BossController` + `BossPhaseConfig` plan on
  warlord). 69–117-line copies → 38–85-line diffs; resolved trees verified byte-parity with
  the pre-refactor scenes (values pinned in `test_archetype_overrides_pinned`).
- Root nodes renamed `EnemyBase` → `<Archetype>Enemy`, matching basic/fast/heavy.
- New guards keep it fixed: `tests/python/test_regress_enemy_scene_inheritance.py`
  (static: inheritance contract, no re-declared shared nodes, per-archetype override
  goldens) and `tests/unit/test_enemy_scene_inheritance.gd` (engine-side: instantiates all
  8 scenes and asserts shared nodes are present, typed and script-wired identically).
- `enemy_base.tscn` is now the single source of truth for all 8 archetypes: one edit lands
  on the whole roster.

## [Unreleased] — UI/UX polish pass (2026-09-08)

Presentation-only pass over the existing screens. **No new gameplay systems, no
new screens, no changes to run/combat/meta logic** — every fix is layout,
hierarchy, spacing, colour, feedback or Android fitness.

### New: one shared layout solver (`scripts/ui/ui_layout.gd`)

`UiLayout` is a pure, static solver that returns every gameplay-overlay rect
(top strip, vitals, minimap, boss frame, banner, toast, virtual stick, attack /
dodge / swap cluster, skill bar) from just the safe-area size and the
accessibility text scale. `ui_root._layout()` now feeds that single solution to
`GameHud.apply_layout()`, `TouchControls.apply_layout()` and the remaining
overlays, replacing the scattered magic offsets (`Vector2(290, 160)`,
`width * 0.5 - 160`, `width < 850`, `height - 210`, …) that produced the
overlaps.

Guaranteed and asserted at runtime by `_test_layout_solver` in
`tests/ui/ui_test_runner.gd`, over 12 resolutions (16:9, 18:9, 19.5:9, 20:9,
4:3, 1600x720 ultrawide, 720x1280 / 1080x2340 portrait, 640x360 floor) × text
scales 1.0 / 1.4 / 2.0:

- every rect lies inside the safe area;
- no two overlay elements overlap;
- attack / dodge / swap are never below the 88px touch floor;
- when a short screen genuinely has no room, the message band collapses to zero
  height and the element is hidden, instead of stacking onto the controls.

### Fixed

- **Overlapping overlays**: banner over the minimap and vitals, boss frame over
  the vitals column in portrait, toast under the skill bar, and (at 200% text)
  the skill bar landing on the action buttons.
- **Wrong anchors**: the HUD toast and the banner's coach line used fixed
  `PRESET_BOTTOM_WIDE` / `PRESET_TOP_WIDE` offsets that drifted off-screen on
  non-16:9 panels; both now follow the solved rect.
- **Joystick drew in the wrong space**: the active base/knob were drawn using
  screen coordinates inside a `_draw()` that is control-local, so the stick
  rendered offset from the thumb. Resting hint is now centred in its capture
  area, active base/knob draw correctly.
- **Text clipping**: HUD labels wrapped mid-word inside a fixed-width strip;
  they now use `OVERRUN_TRIM_ELLIPSIS`, the scrims clip, and compact wording
  refreshes on rotation (`_relabel`). Skill names abbreviate on narrow slots.
- **Confirmation dialog** was hardcoded to 500x220 and clipped its message at
  large text; `_popup_confirm()` sizes it from the viewport and text scale,
  wraps the label and gives both buttons full touch targets.
- **Upgrade grid** flipped 3→1 columns at a hard 1000px cutoff; it now fits
  2 columns where they fit and grows card height at large text.
- **Main menu** secondary row (Armory / Settings / How to play) clipped its
  labels on narrow portrait; it stacks vertically below 560px.

### Touch & feedback

- Touch-target floor unified at 88px (`UiTheme.TOUCH_MIN` / `UiLayout.MIN_TOUCH`)
  and enforced in `UiFactory.button/check` — sliders, option buttons, rebind
  buttons, armory Buy/Close and the HUD Pause button were all below it.
- Action buttons gained a real press state (brighter disc, thicker gold ring,
  outer halo) so a tap is confirmed even when the thumb covers the label.
- Skill slots now read locked / cooling / ready visually (opacity + caption
  colour), not by text alone.
- Theme `pressed` state is deliberately louder than `hover`, since touch has no
  hover; added `font_pressed_color` / `font_focus_color`.

### Visual coherence

- `UiTheme` gained a shared spacing scale (`SPACE_S/M/L`, `RADIUS`) used by the
  factory, cards, grids, menus and panels, replacing ad-hoc 8/10/12/16/24 gaps.
- Rajdhani is now bound for `Label`, `RichTextLabel` and `PopupMenu` too, so no
  control silently falls back to the engine default font.
- HUD top strip and vitals sit on translucent scrims, so score/health stay
  legible over the Ember and Frost arena themes without hiding gameplay.
- Boss frame, banner, toast and touch labels carry text outlines.
- Clearer hierarchy: dominant primary CTAs (Start Run, Resume Run), muted
  supporting copy, destructive pause actions grouped in a secondary row, and a
  subtitle on the Settings/Armory shells.

### CI

- The headless UI suite (`scripts/ui/run_ui_validation.sh`) was referenced by the
  docs but **invoked by no workflow**, so it had never actually run in CI. It is
  now wired into the `godot-tests` job. Wiring it up immediately caught a real
  bug in this branch: `TouchActionButton` seeded `custom_minimum_size` from its
  initial radius, so the Control refused to shrink to a smaller solved rect and
  overflowed the viewport at 960x540. Fixed.
- Current state: **2187 UI checks, 0 failed.**

### Pre-existing bugs surfaced (NOT fixed here — out of scope for a UI pass)

Running the UI suite for the first time also exposed two latent runtime errors
that exist unchanged on `main` (verified against base commit `3751371`). They
are filtered by an explicit, documented `KNOWN_FAILURES` allowlist in the
validation script so the new gate reports UI regressions instead of failing on
day one. Each should be fixed and de-listed:

1. `scripts/core/run_scorekeeper.gd` calls `_combat_log.log(...)`, but
   `CombatLog` defines `record(...)` and has no `log()`. Every run start and
   wave bonus raises `SCRIPT ERROR` and the entry is never recorded.
2. The UI player double returns a `Dictionary` where a `ProgressionComponent` is
   expected, so `get_stat` lookups error on a base object of type `Dictionary`.

### Notes

- Orientation stays `sensor_landscape` per `docs/ART_STYLE.md`; the stretch
  settings are now commented to explain the tall-panel behaviour. Portrait
  geometry is still solved and tested because the safe area can be portrait-ish
  mid-rotation and on foldables.
- Verified: `tool/validate_resources.py`, `tool/validate_assets.py`,
  522 Python regression tests (new suite:
  `tests/python/test_regress_ui_layout_polish.py`) and `gdparse` on all UI
  scripts. The Godot headless UI suite could not be executed in this sandbox
  (no network access to a Godot binary); it runs in CI via
  `scripts/ui/run_ui_validation.sh`.

## [0.6.0-dev] — In Development

- **Version bump**: `0.5.0→0.6.0` (version code `2→3`).
- Initiated development cycle for `v0.6.0`.
- **Character integrity**: `PlayerStart` moved off the central landmark so the hero
  is visible at run start; `player.tscn` gains a fallback `Body` capsule
  (load_steps `26→28`) mirroring the enemy pattern; `character_visuals.gd` fixes
  double-counted fit scale in grounding, hides Knight equipment before measuring,
  skips hidden/mesh-less nodes in bounds, warns (with `ResourceLoader.exists`
  pre-check) on mount failure, plants the ground shadow on the mount, and exposes
  start/stop breathing; `PlayerAnimation`/`PlayerEquipment` re-bind late mounts,
  stop before animation-library surgery, and rest the death pose; `PlayerFeedback`
  re-collects late-mounted weapon meshes.
- **Enemy facing**: all 8 `EnemyAnimator` nodes set `yaw_offset_degrees = 180.0` —
  every model authors forward as +Z (verified from bind-pose joints) while
  `face_direction` aims VisualRoot −Z at the player, so enemies faced backwards.
- **Spawn safety**: `ArenaDecorator._open_spot` keeps props/pillars 2.5 m clear of
  `PlayerStart` so runs can't begin inside decoration collision.
- **Lint**: repo-wide `gdlint` clean (renamed `_p_check`/`_pl` locals).
- **Startup stability follow-up**: deterministic dependency-first autoload order
  (`project.godot`: EventBus → SaveManager → AudioManager → ContentRegistry →
  GameRoot → SceneRouter → RunAnalytics → TestHarness) so singleton `_ready` code
  can rely on its dependencies existing — load-bearing now that
  `ContentRegistry.refresh_all` drives `AudioAssetIntegrator` registration, which
  needs `AudioManager`; documented inline in `project.godot`.
- **Authoritative end-of-run bests**: `game_root.gd:_finalize_run` re-reads
  `SaveManager.get_best_score`/`get_best_wave` (guarded by `has_method`) and takes
  `maxi` with the in-memory values, so reported bests can never regress below what
  is persisted even if a stats signal was dropped mid-run.
- **Richer mount diagnostics**: `character_visuals.gd` adds `model_path(role)` and
  `_report_mount_issue` (push_warning always + EventBus diagnostic mirror), and now
  reports the four previously silent abort sites (missing mount point, non-Node3D
  model root, no usable geometry, no visible mesh bounds); `visual_mount.gd` names
  the resolved model path and whether the primitive Body fallback is present
  ("primitive Body fallback kept" / "NO FALLBACK VISUAL PRESENT").
- **Bootstrap validation**: `main.gd` reports errors for a missing `WorldRoot`,
  a null arena config guard, an arena that fails to instantiate (naming
  `resource_path`), player scene load/instantiate failure, a null player aborting
  system creation, SpawnManager/WaveManager instantiation failure, and wave start
  without spawn/wave systems; adds `_validate_player_visual` which verifies
  VisualRoot/CharacterModel/Body at spawn time.

## [Unreleased] — Runtime verification fixes (2026-09-08)

Found by the headless E2E harness (`tests/verify_flow.gd`, 193 checks over two
full menu→run→game-over loops, all passing with zero script errors). Each fix is
a one-line correction of existing intent; no gameplay or architecture changes.
- **SFX variant volume restored**: `AudioStreamRandomizer.random_volume_db` does
  not exist (Godot 4.4 uses `random_volume_offset_db`); every pooled cue errored
  at registration and lost its ±3 dB humanization.
- **Run-start log error removed**: `RunScorekeeper` called the nonexistent
  `CombatLog.log`; the API is `record`, so the "Run started" entry now lands.
- **Player model mounts again**: `CharacterVisuals._bounds` took `Node3D`, so any
  imported rig (AnimationPlayer child) failed the mount and the hero stayed a
  primitive with no animation. The parameter is now `Node`, matching the body.
- **Boss phases work**: `HealthComponent.reset` emitted a transient 0/max state
  (current HP restored after the emit), so every boss spawned in Enrage with a
  phantom phase event + sting and phases never advanced afterwards.
- **Post-run music bed restored**: `run_ended` always lands after the game-over
  state hook, so requesting SILENT there stomped the explicit game_over→VICTORY
  bed with dead silence; it now restates VICTORY (same-state is a no-op).

## [Unreleased] — Audio & feedback polish (2026-09-08)

No new gameplay; feel-only fixes to existing audio, buses, and feedback.
- **Missing audio connected**: every `UiFactory` button now ticks (`ui_confirm` /
  `ui_back` by caption; those cues previously had zero call sites), plus upgrade
  cards, armory buy/close, option rows, toggles, the leave-run dialog, keyboard
  pause/resume, and the run-end `game_over` sting in `GameRoot._finalize_run`.
- **Double plays removed**: level-up no longer stacks `upgrade_select` over
  `level_up`; weapon switch plays `player_switch` exactly once (`equip` kept as a
  fallback via the `play_sfx` return value instead of a layered double).
- **Consistent mix**: enemy/pickup/upgrade cues moved from 0 dB to the catalogue's
  suggested gains (`-8`, spawns `-10`, explosions `-6`); enemy cues gained slight
  pitch variance; `AudioManager.play_sfx` now clamps volume/pitch (the
  `_validated_volume` helper was previously unused).
- **Music lifecycle**: menu bed seeds on fresh launch (previously silent until the
  first return to menu); heat resets on run start; crossfades capture the outgoing
  level so rapid state changes don't pop; recorded tracks register before tracking
  starts so launch audio is never the procedural placeholder.
- **Background/foreground**: `AudioManager` mutes the master bus on
  application-pause/focus-loss and restores on resume, combined with (never
  overwriting) the player's mute setting.
- **Volume controls**: settings sliders preview live on the mixer without touching
  saved data; leaving without saving restores the saved mix (`cancel_preview`).
- **Enemy hit feedback rebuilt**: `EnemyFeedback` no longer touches the
  nonexistent `Node3D.modulate` (runtime errors on every hit, no flash) — color
  flashes use a per-enemy overlay material, scale pops are relative so archetype /
  elite scales survive hits, overlapping flashes replace instead of piling up,
  hit/crit juice honors reduced motion, and the death sink fills the 0.8 s free
  window instead of vanishing early.
- **Softer transitions**: announcement banner entrance pop (reduced-motion aware),
  boss bar fade in/out with spawn-token guard, fallback idle clips forced to loop.
- **Hygiene**: integrator re-registration resets its counters; no new players,
  buses, or content — pool and memory footprint unchanged (16 SFX + 2 music + 1
  legacy music voice).

## [0.5.0] — Polished presentation & release fix (2026-09-08)

- **Arena identities**: per-arena themes (ember 0.12/0.85 fog 0.028 sun1.85, frost 0.18/0.82 fog0.024, default) plus central `Landmark` (forge lava 4.5+light2.2, crystal prisms 1.8, obelisk+cap) via `arena.gd:THEMES`+`_spawn_landmark`; `arena_decorator` distinct clutter (ember 18+5 braziers, frost columns+ice shards, default stone circle).
- **Character polish**: `character_visuals.gd` ground shadow + breathing bob, `player_animation` skill/victory clips (10 skill map, Cheer on level/boss), `enemy_animator` stun/cast + telegraph sync, `boss_controller` phase visuals (tint/scale/light) + audio.
- **Combat feel**: pooled bursts 10×22/0.68s + emissive rings, crit gold 0.82+1.05, elite aura, hitstop 0.04/0.16, camera combat shake wiring (skill/wave/boss).
- **Audio**: `procedural_sfx` 10→28 cues, `skill_controller`/`experience`/`wave_manager`/`boss_controller` play `skill_cast`/`ready`/`level_up`/`wave_started`/`completed`/`boss_*`; `catalog.json` 7 new cues.
- **UI / mobile**: `upgrade_panel` rarity borders, `touch_controls` 64/52 thumb-friendly, `camera_rig` impulse, safe-area.
- **CI fix**: `android.yml` `publish-release` now triggers on `release: published` (was skipped) plus tags/dispatch, tag fallback uses `event.release.tag_name`; version bump `0.4.0→0.5.0` code 2 to unblock `v0.5.0`.

## [Unreleased] — Enemy/encounter ecosystem pass (Agent 2, 2026-09-08)

- **Roster models + animations integrated**: every archetype mounts its catalogued
  model via the new `EnemyAnimator` (ModelVisual fitting, untouched physics), with
  idle/run loops, windup-scaled attack clips, hurt and death one-shots
  (Skeleton Minion/Rogue/Warrior/Mage, Rat, Spider, Demon, BlueDemon).
- **Distinct combat identities**: Dashers telegraph a straight-line charge with a
  single contact hit and a vulnerable recovery (new `EnemyDashState`); Exploders
  plant and blink inside fuse range before self-detonating through the normal
  exactly-once death path (new `EnemyFuseState`); Fast skirmishers back-pedal after
  each sting; Heavies/Bosses gained poise so telegraphed swings are not
  perma-staggered; melee windups now abort cleanly when the target escapes.
- **Ranged polish**: kiting when crowded, windup telegraphs (flash + sound), and
  target-leading volleys through the existing ProjectilePool.
- **Splitter burst**: children burst around the parent's death position with
  outward scatter and extend the SpawnLedger plan (`register_direct_spawn`), with a
  queue fallback when direct spawning is impossible — accounting stays exact.
- **Boss encounter**: warlord phases authored as `BossPhaseConfig` resources on the
  BossController node; deterministic (run-seeded) ability picks; real telegraphs,
  travelling charge, recovery windows and a phase-transition stagger; UI stays
  event-driven through the existing `boss_spawned`/`boss_phase_changed` contracts.
- **Elite affix behavior completed**: VAMPIRIC heals from damage dealt, FRENZIED
  attacks faster below half health (both via EnemyBase hooks, configs untouched).
- **Spawn/anti-overlap**: opening burst pacing, deterministic per-marker jitter,
  per-enemy approach offsets (fan-out), and enemy/enemy collision so packs cannot
  stack in one body.
- **Feedback/audio**: telegraph flash, longer death window for death animations,
  and three new CC0 synthesized cues (`enemy_windup`, `enemy_dash`,
  `enemy_explosion`) auto-registered from `data/audio/`.
- **Robustness**: enemy scripts resolve EventBus/AudioManager through the tree
  (null-safe under the bare headless harness), unblocking real enemy integration
  tests; fixed a duplicate-member block in `enemy_config.gd`.
- **Tests**: new `test_enemy_behaviors.gd` unit suite (ledger direct-spawn
  accounting, boss phase math, phase/config validation) plus the
  `_run_enemy_encounter_integration` section in `run_tests.gd` covering state
  transitions, attack timing/whiff, poise, dash, fuse, ranged kiting, vampiric /
  frenzied hooks, boss phases + deterministic abilities, and the full SpawnManager
  wave cycle (burst, failed-spawn distinction, splitter bursts, no false clears).

## [Unreleased] — Environment / presentation pass (Agent 4, 2026-09-08)

### Visual
- **Live character + enemy models**: `scripts/visuals/character_visuals.gd` mounts the
  approved Knight + 8 archetype models onto `VisualRoot/CharacterModel` (height-fit,
  foot-grounded, +Z→−Z yaw, optional idle loop) with a primitive fallback; player wired
  via a scene mount node, enemies via a narrow `EnemyBase` hook. No gameplay change.
- **Arena identity**: `ArenaDecorator` now places approved KayKit dungeon props
  (pillars/columns, banners, torches, crates, barrels, rubble) with per-arena
  compositions + primitive fallback; `arena.gd` applies per-arena sky/fog/sun/ambient
  and floor/wall tint themes for Default, Ember Crucible and Frost Hollow.
- **Pooled VFX** (`scripts/visuals/effect_director.gd`): mobile-capped GPU bursts +
  ground rings for enemy spawn/death, wave start/completion, pickups, boss spawn/slain
  and status effects (via existing `EventBus` signals; no gameplay edits).

### Audio
- **Approved audio registered**: `AudioAssetIntegrator` reads `assets/catalog.json`
  at startup and registers the recorded SFX pools + looping menu/combat music onto the
  existing `music_*` state cues over the procedural fallback.

### Validation
- Unit suite `test_character_visuals` + `validate_asset_imports` presentation checks
  (role model import/idle coverage, VFX sprite textures). Full Android CI green.

## [Unreleased] — Asset audit and medium-detail upgrade (2026-09-08)

- Verify all 191 prior downloads; add 31 licensed/locked files (~10.30 MiB),
  including 23 models and detailed stone maps. Total: 222 files, 81 models.
- Cover all current character, weapon, pickup, skill and arena roles in the catalogue.
- Replace live flat arena materials and identical pickup prisms; retain physics,
  collection rules and missing-art fallback. Character/equipment integration pending.
- Validate complete content-ID coverage, runtime source references and shared
  licence notices; add material/model import checks and normalization tests.
- Document upstream upgrade decisions and remaining integration in ASSET_AUDIT.md.


## [Unreleased] — Arena build-out · weapons, skills, arenas, enemies, meta

### Release engineering
- **v0.4.0 published** (2026-09-08) — first release via the tag-push path; CI run
  #34171607635 built, tested and attached `LastStandArena-debug.apk` (ARM64,
  debug-signed) + `SHA256SUMS.txt` to the Release.
- Workflow now also triggers on **`release: published`**, so creating a Release in
  the GitHub UI runs the full build + publish pipeline (previously only tag pushes
  or manual dispatch did — and manual dispatch needs elevated token permissions).
- New `scripts/release.sh vX.Y.Z`: one-command, guardrailed release (refuses dirty
  trees, duplicate tags, and version drift between the tag, `export_presets.cfg`
  `version/name`, and the CHANGELOG; then pushes the tag for CI to publish).

### Added
- **Data-driven weapon loadout** — `WeaponConfig` resources (`data/weapons/`, 6 shipped:
  gladius, sentinel_spear, stormhammer, sunbow, twinfangs, warreaxe) auto-discovered by
  `ContentRegistry`; `WeaponManager` owns the 2-slot loadout + cooldowns + switching
  (Tab / gamepad Y / touch button), `MeleeResolver` scores arc hits, `ProjectilePool`
  serves pooled projectiles for volleys and enemy ranged attacks.
- **Active skills + status effects** — `SkillConfig` resources (`data/skills/`, 5 shipped:
  bladestorm, frost_nova, phantom_rush, seismic_slam, warcry), `SkillController`
  (charges/cooldowns, Q/E/R + tappable HUD skill bar), `StatusManager` (bleed/burn/
  guard/regen/shock/slow/stun/warcry with refresh/stack rules), `AreaDamage` helper.
- **2 new arenas** — `ember_crucible` + `frost_hollow` configs (share the arena scene)
  with `ArenaDecorator` (deterministic props), `ArenaHazards` (floor fields),
  per-arena music cue (consulted by `MusicManager`), and unlock waves.
- **5 new enemies** — dasher, exploder, ranged, splitter (spawns fast mites on death),
  warlord (3-phase boss via `BossController`); stun gating + slow scaling in `EnemyBase`,
  elite affixes (`EnemyEliteAffix`), hit-flash/death-sink juice via `EnemyFeedback`.
- **Combat depth** — `RunScorekeeper` combo (4s window, score events, kill feed in
  `CombatLog`), `DamageNumberLayer` crit popups, `HitstopManager` (hitstop + trauma
  shake), `PickupManager` (6 drops: antidote/coin_cache/health_orb/magnet_core/
  stamina_brew/xp_gem).
- **Wave director** — 7 static mutators (`WaveMutators`: swift_horde/iron_hide/
  elite_surge/glass_cannon/bounty_hunt/volatile_mix/ember_winds) resolved per wave,
  wave + mutator banner announcements, adaptive `DifficultyDirector`, endless planner
  scaling.
- **Run flow** — pause overlay + settings-from-pause, game-over run summary,
  `SettingsPanel` (volumes, mute, motion, vibration, contrast, FPS cap, quality tier,
  persisted remapping via `InputRemapper`), `TutorialManager` first-run coach speaking
  through the HUD announcement banner.
- **Meta game** — `MetaProgression` wallet (banks half the run currency) + 8-item armory
  (5 stat tracks, 2 weapon unlocks, Bladestorm manual) with a spendable `ArmoryPanel`
  shop; `Achievements` (19 achievements, persistent); playable `DailyChallenge` (shared
  daily seed, fixed mutators + starter weapon).
- **Audio** — `MusicManager` (menu/calm/battle/battle/boss/victory states, heat-driven
  intensity layers, crossfades); `ProceduralSfx` synthesizes every referenced cue
  (10 SFX + 5 music beds) so the game is never silent — real drops in `data/audio/`
  (`.tres`/`.ogg`/`.wav`/`.mp3`) always take precedence.
- **HUD/widgets** — skill bar, tactical minimap, boss HP frame, announcement banner,
  damage numbers, combat-event kill feed, armory + daily-challenge menu entries.
- **Debug tooling** — `PerformanceMonitor` (rolling FPS + auto quality scaling, feeds
  the damage-number budget).
- **Unit tests** — 9 new suites (`test_rng_tables`, `test_weapons`, `test_status_skills`,
  `test_area_combat`, `test_drops_elites`, `test_director_mutators`, `test_meta_misc`,
  `test_planner_extended`, `test_procedural_sfx`); ~200 checked assertions, all
  autoload-independent.

### Changed
- `EnemyBase` integrates `StatusManager` (stun pauses AI, slow scales motion);
  `SpawnManager` supports elites/affixes and wave-modifier scaling (hp/damage/speed/
  score/elite/explosive); `WaveManager`/`WavePlanner` apply mutators + endless scaling.
- `SaveManager` schema 3: tutorial completion, achievements, meta wallet/ranks.
- `SettingsData` gained getters; `HealthComponent` gained `get_max()`;
  `ProgressionComponent` accepts `skill_cooldown_multiplier` + `add_permanent_bonus()`.
- `Main` builds per-run systems (projectiles, pickups, hitstop, perf, decor, hazards)
  and persistent directors (music, achievements, meta, tutorial).
- New `skill_1/2/3` input actions (Q/E/R + joypad shoulder/trigger).

### Fixed (audit + fix pass)
- Pause soft-lock: `PAUSED` had no outgoing transitions, so resume/restart/menu
  from pause were rejected; added `PAUSED` transitions and made `GameRoot`
  process while paused so the keyboard toggle works (UI already ran always).
- Splitter wave-stall: children extending the plan after the pacing timer stopped
  left the wave unwinnable; the timer restarts when the plan extends (same guard
  for boss summons).
- Enemies were immune to slows/stuns: `enemy_base.tscn` lacked the `StatusManager`
  node the warlord already had; added (auto-binds health).
- Boss summons never spawned (`summon_requested` unwired); the spawner now extends
  the plan on summon. New `boss_slain` signal resets boss music to battle.
- Payload status riders never applied: `apply_damage` on player/enemy now forwards
  `payload.status_effects` to the local `StatusManager`.
- Silent cues wired: pickup collection + enemy spawn sounds; level-ups announce on
  the banner; the adaptive director now receives player-damage events.
- Hitstop/trauma never triggered: crits/deaths now pulse the `HitstopManager`.
- Camera shake permanently drifted the lens; base position is captured + restored,
  reduced-motion initializes from save, and arena camera profiles apply at build.
- Arena validation errors surface at startup; save flushes on quit request.
- Touch buttons work with mouse (desktop parity) and draw centered; HUD seeds from
  the live run so fresh runs never render stale widgets; `reload_finished` forwards
  from weapon instances; `AUDIO_MANIFEST.md`/README status updated.

### Modularized
- Split the 10 largest scripts into focused modules (public APIs unchanged):
  `ui_root` → `UiText` + `UiFactory` + `GameHud` + `UpgradePanel` (658→363);
  `player` → `PlayerLocomotion` + `PlayerBuild` (617→489);
  `enemy_base` → `EnemyLocomotion` + `EnemyNavigator` + `EnemyStriker` (548→392);
  `spawn_manager` → `SpawnLedger` + `SpawnPlacer` (466→353);
  `game_root` → `RunScorekeeper` + `UpgradeService` (442→359);
  `skill_controller` → `SkillExecutor` (398→200);
  `save_manager` → `SaveSchema` (352→241);
  `attack_controller` → `ComboChain` (321→298);
  `content_registry` → `ContentLoader` (310→210);
  mutator resolution → `WaveMutators.resolve_for_wave` (317→305).
- `DamagePayload.with_amount()` clone helper (mitigation/shield pipelines).
- New `test_extracted_modules` suite (ComboChain/SpawnLedger/SaveSchema/UiText/payload).
- Fixed: `ContentRegistry.refresh_all()` now rebuilds fresh tables, so repeated
  refresh/validate no longer reports every id as a false duplicate.

## [Unreleased] — 2026-09-07 · Core 3D asset kit

### Added
- **178 downloaded asset files + 13 preserved source notices (24.75 MiB):**
  4 rigged KayKit characters with embedded animation libraries, 11 weapon/shield
  models with their buffers/textures, 37 arena models, 6 pickup models, 15 particle
  textures, 55 UI/upgrade images, 2 Rajdhani fonts, 29 SFX and 2 Ogg music loops.
- **Asset catalogue** (`docs/ASSET_CATALOG.md`, `assets/catalog.json`) mapping the
  player, Basic/Fast/Heavy enemies, all 10 upgrades, effects, props and audio cues
  to actual downloaded files. Exact clip names and integration notes included.
- **Per-file source lock** (`assets/manifest.json`): reviewed creator/licence,
  immutable source commit, exact download URL, original/local path, size, SHA-256
  and acquisition date. Updated visual/audio manifests and stored licence notices.
- **Offline format/dependency/coverage validation**, 28 Python tests, optional
  Khronos glTF validation, and a native Godot import smoke test for CI/builds.

### Changed
- Replaced the empty downloader scaffold with an approved-source-only restorer:
  mandatory size/hash checks, read-only `--verify`, explicit `--repair`, safe paths,
  atomic writes and pack selection. No credentials or runtime downloads required.
- Android export presets retain asset/font licence notices. `.gitattributes`
  prevents line-ending conversion from invalidating source checksums.
- Build/CI paths verify assets and exercise native Godot resource imports.

### Scope / validation
- **Downloads only, not an art/gameplay integration milestone.** Live character,
  arena, UI and audio wiring remain unchanged. No combat/camera/progression changes.
- 191 file checks, 28 Python tests and 25 existing resource structural checks pass.
  All 58 models pass Khronos validation with 0 errors; 32 upstream skinned-hierarchy
  warnings are documented. All 31 audio files decode and contain sound.
- Godot/Android execution was unavailable locally (engine not installed; release
  download host unreachable). Native import checks were added but not run here.

## [0.4.0] — Phase 4 · Data-driven progression & upgrade loop

### Added
- **Real upgrade library** under `data/upgrades/` — 10 `UpgradeConfig` resources
  (`vitality`, `swift`, `power`, `haste`, `fortified`, `hunter`, `reach`, `force`,
  `scavenger`, `bloodlust`), auto-discovered and validated by `ContentRegistry`.
- **Deterministic upgrade selection** — new `UpgradeSelector` seeds a local RNG from
  `(run_seed, wave)`; returns exactly 3 valid choices (fewer when the pool is smaller),
  never duplicates, and respects disabled / unlock_wave / prerequisites / exclusions /
  max-stacks / weight. It never touches the global RNG.
- **GameRoot progression commands** — `present_upgrade_selection_for_wave()` and
  `request_upgrade_selection()` on the canonical state machine
  (`PLAYING → WAVE_TRANSITION → UPGRADE_SELECTION → PLAYING`). Only offered + still-legal
  ids can be selected; arbitrary ids are rejected.
- **WaveManager upgrade integration** — after a wave whose config sets
  `upgrade_after_completion`, the next wave is held until a valid upgrade is selected;
  otherwise waves continue through the normal inter-wave transition.
- **Explicit modifier semantics** (documented in `docs/EXTENDING.md`): multiplicative
  `base*(1+Σ)`, additive `base+Σ`, cooldown `base*(1+Σ)` with negative = reduction (clamped
  `>=0.05`), resistance clamped `[0,1]`.
- **Modifier → gameplay wiring**: max HP (with full-HP top-up 100→120), move speed,
  attack damage, attack cooldown, damage resistance, attack range, knockback, score /
  currency multipliers, and heal-on-kill all now change real behaviour.
- **Upgrade UI** — real selection cards (interactive buttons) with rarity colouring, stack
  counts, selection locking, and an applied-effect toast that respects reduced-motion.
- **Real dodge** with temporary invulnerability, burst movement, camera-relative direction,
  arena clamp and a proper cooldown.
- **Combo completion** — decays to 0 after a no-kill window, tracked in the run summary;
  no increase after death.
- **Authoritative spawn/wave accounting** — `SpawnManager` tracks planned/spawned/pending /
  active/defeated/failed explicitly; a failed spawn is retried up to a bound and counted as
  failed (never as a defeat) so it can't under-fill or falsely complete a wave.
- **`EventBus.enemy_damaged`** now emitted exactly once per accepted enemy damage.
- **Tests** — new headless suites `test_upgrades`, `test_upgrade_selection`,
  `test_progression`, `test_combo`; all existing + new suites pass in CI.

### Changed
- `ProgressionComponent` is the runtime source of truth; `RunState.selected_upgrades` /
  `active_modifiers` are a serializable mirror kept in sync by GameRoot.
- Fixes an existing UI bug where `_sync_from_state()` only ran once in `_ready`, so panels
  (HUD / pause / game-over / upgrade) never switched on state change.

### CI

- The headless UI suite (`scripts/ui/run_ui_validation.sh`) was referenced by the
  docs but **invoked by no workflow**, so it had never actually run in CI. It is
  now wired into the `godot-tests` job. Wiring it up immediately caught a real
  bug in this branch: `TouchActionButton` seeded `custom_minimum_size` from its
  initial radius, so the Control refused to shrink to a smaller solved rect and
  overflowed the viewport at 960x540. Fixed.
- Current state: **2187 UI checks, 0 failed.**

### Pre-existing bugs surfaced (NOT fixed here — out of scope for a UI pass)

Running the UI suite for the first time also exposed two latent runtime errors
that exist unchanged on `main` (verified against base commit `3751371`). They
are filtered by an explicit, documented `KNOWN_FAILURES` allowlist in the
validation script so the new gate reports UI regressions instead of failing on
day one. Each should be fixed and de-listed:

1. `scripts/core/run_scorekeeper.gd` calls `_combat_log.log(...)`, but
   `CombatLog` defines `record(...)` and has no `log()`. Every run start and
   wave bonus raises `SCRIPT ERROR` and the entry is never recorded.
2. The UI player double returns a `Dictionary` where a `ProgressionComponent` is
   expected, so `get_stat` lookups error on a base object of type `Dictionary`.

### Notes / limitations
- Visual assets remain primitive Godot primitives; no external art/audio was introduced
  in this phase (none with verified licensing were sourced). Optional audio cues degrade
  gracefully to silence. See the Phase 4 report.

## [0.3.2] — Fix: Android APK export green in CI (build template + export-time compile)

### Fixed
- **Android build template installed into the project.** Godot's Gradle Android export
  (`gradle_build/use_gradle_build=true`) needs the Android build *source* template in the
  project, not just the runtime export templates in the user data dir. New
  `scripts/install_android_build_template.sh` mirrors Godot's own installer: it unzips
  `android_source.zip` into `res://android/build`, writes an empty `.gdignore`, writes the
  template identifier into `res://android/.build_version`, and restores the Unix
  executable bit on `gradlew` (Python's `zipfile` does not preserve exec bits, which
  caused `android/build/gradlew: Permission denied`). `docs/BUILD.md` documents it.
- **CI setup.** The `build-android` job now (1) installs runtime export templates
  canonically via `chickensoft-games/setup-godot` (`include-templates: true`) and verifies
  them with the idempotent `scripts/install_export_templates.sh`, (2) adds a Temurin
  JDK 17 (Godot's Gradle build needs a JDK), (3) installs the Android build template into
  the project, and (4) captures/annotates Godot export output for diagnosability.
- **Export-time GDScript compile errors fixed.** Android export compiles every script,
  which the headless unit runner/import do not, exposing latent problems now resolved:
  `targeting_component.gd` renamed `set_owner()` → `bind_owner()` (it overrode
  `Node.set_owner`); explicit types added in `character_controller.gd`, `attack_controller.gd`,
  `spawn_manager.gd` and `ui_root.gd` (Variant-inferred locals); `DisplayServer.FEATURE_HAPTICS`
  removed in `player_feedback.gd` / `touch_action_button.gd` (removed from the engine in 4.3+).
- **Result.** `.github/workflows/android.yml` `build-android` job is green end-to-end:
  headless unit tests, resource/asset validation, **`godot --export-debug "Android"`** and the
  non-empty-APK check all pass; the debug APK is uploaded as the `LastStandArena-android`
  artifact (milestone validation artifact). The Android build toolchain is not reachable
  from the authoring sandbox, so this was verified by running the real GitHub Actions CI.

## [0.3.1] — Fix: CI Android export templates not installed

### Fixed
- The CI "Install matching Android export templates" step could exit 0 without actually
  placing any templates (no `set -e`, silent `curl`/`unzip`/`cp` failures), so the later
  `godot --export-debug "Android"` step failed with *"Android build template not
  installed in the project"*. The install logic is now a shared, strict script
  `scripts/install_export_templates.sh` (used by both the `build-android` and
  `publish-release` jobs) that downloads with `curl --fail`, extracts with Python's
  `zipfile`, copies into `~/.local/share/godot/export_templates/<version-string>/`
  (dot before `stable`, e.g. `4.4.1.stable`), and fails loudly unless
  `android_debug.apk`, `android_release.apk` and `android_source.zip` are present.
- `docs/BUILD.md` documents the script and adds a troubleshooting entry for the
  "Android build template not installed" export error.

## [0.3.0] — Phase 3 · Integrated run loop (menu → waves → game over)

### Added (Phase 3)
- **Enemy AI state machine** (`EnemyStateMachine` + `EnemyState` base and concrete
  `Idle`/`Chase`/`Attack`/`Hurt`/`Dead` states). Lightweight `RefCounted` states mutate
  the host `EnemyBase` only through its public command surface and request transitions
  via `change_to()`; every route funnels through one `change_to()` so lifecycle and
  bookkeeping stay in one place.
- **EnemyBase movement + behaviour host**: real `CharacterBody3D` movement (desired
  dir/speed, gravity, navigation-aware steering via a `NavigationAgent3D`, decay + stuck
  recovery for knockback, arena-bounds clamping) driven by the state machine in
  `_physics_process`. Preserves the Phase 2 command API and the exactly-once death /
  `enemy_killed` / score guarantees. Adds `set_bounds`, `apply_difficulty`,
  `get_effective_speed/damage`, `perform_enemy_attack()` (one-queried melee through the
  player `HealthComponent`), `get_navigation_direction`, and a debug snapshot.
- **Two new archetypes**: `fast` ("Stinger", low HP / fast / short cooldown) and
  `heavy` ("Brute", high HP & damage / slow / high knockback resistance / long
  windup+cooldown), added to `data/enemies/` + `scenes/enemies/` and auto-discovered by
  `ContentRegistry`.
- **SpawnManager** (`scripts/enemies/spawn_manager.gd` + scene): owns flattened spawn
  queues, seeded deterministic point pick, max-simultaneous cap, pacing timer, active
  enemy registration/removal, `all_cleared` detection and run-end AI deactivation. Does
  NOT own score/waves.
- **WavePlanner** (`scripts/waves/wave_planner.gd`): pure deterministic composition
  table, `WaveConfig` builder and difficulty scalars for waves 1..N.
- **WaveManager** (`scripts/waves/wave_manager.gd`): drives `WavePlanner`, feeds
  rollouts + difficulty to the `SpawnManager`, listens for `enemy_spawned` /
  `all_cleared`, and moves through the GameRoot state machine for clean inter-wave
  transitions. Completion bonuses are announced via `EventBus.wave_completed` and scored
  centrally by GameRoot (exactly once) — WaveManager never owns score/saves/upgrades.
- **Main composition**: builds/tears down the world (arena + player + camera +
  `EnemyContainer` + SpawnManager + WaveManager) under `WorldRoot`, starts the wave
  director on `PLAYING`, deactivates AI and stops the director on `GAME_OVER`/`MAIN_MENU`.
- **GameRoot run hooks**: `record_current_wave`, `award_wave_completion_bonus`,
  `begin_wave_transition` / `end_wave_transition`, and elapsed-run-time tracking —
  keeping scoring/wave accounting centralized and exactly-once.
- **Headless unit suite** `tests/unit/test_waves.gd`: WavePlanner determinism / counts /
  scaling and validation of the three real archetype `.tres` resources.
- **TestHarness smoke** items for the Phase 3 loop (`enemy_spawns`, `enemy_takes_damage`,
  `enemy_dies`, `score_increases`, `wave_progresses`) flipped to deterministic green
  checks.

### Fixed / Notes
- Added `EnemyBase.state_machine_change_to()` facade (states were calling it but it was
  missing).
- `gdlintrc`: `max-public-methods` disabled because `EnemyBase` intentionally exposes
  >20 public methods.
- Deterministic arena navigation floor (flat convex `NavigationMesh`, no runtime baking)
  and bounds/min-spawn-distance APIs on `Arena`.
- Remaining known limitation: full menu→wave→game-over play-through and APK artifact are
  verified via Godot user runs and GitHub Actions (no Godot binary is reachable in this
  sandbox).

## [0.2.1] — Fix: Godot 4.4 compile errors (parse / type-inference)

### Fixed
- `save_manager.gd`: renamed the static `_get(...)` helper to `_dict_get(...)` — it
  collided with `Object._get(StringName)`, breaking the whole script ("function
  signature doesn't match the parent"). Declared `raw`/`previous` (read from
  `_read_raw`, which returns Variant) as explicit `Variant` instead of `:=`.
- Tests: replaced `var X := load(...).new()` with direct references to the registered
  `class_name` types (`DamagePayload`, `DamageResult`, `HealthComponent`,
  `CombatQuery`, `Scoring`, `EnemyConfig`, etc.) so `.new()` is statically typed and
  no longer triggers "cannot infer the type" / "inferred from a Variant value" errors.
- Added `class_name` to the `FakeClock` and `FakeSaveStorage` test doubles.
- `combat_query.gd`, `targeting_component.gd`, `character_controller.gd`: removed
  ternaries whose branches produced a Variant (`t is Node3D`, `c is Node3D`,
  `get_camera_3d() if ...`) that would fail type inference when those scripts load.

These were latent in Phases 1-2 and surfaced on the first real
`godot --headless --path . --script res://tests/run_tests.gd` run.
All notable changes are tracked per implementation phase.

## [0.2.0] — Phase 2 · Combat + first enemy (in progress)

### Added (Phase 2)
- **Combat query layer** (`scripts/combat/combat_query.gd`): pure, deterministic arc/
  range hit selection for melee swings (headless unit-testable).
- **Melee hit resolution** in `AttackController`: telegraph (`windup`) → arc query over
  the `enemies` group → validated `DamagePayload` → apply → `attack_hit`, with crit
  chance, knockback, and damage/range derived through the player `ProgressionComponent`.
- **Enemy base** (`EnemyBase` CharacterBody3D + scene): lifecycle, `initialize(config,
  target, seed)`, damage intake, idempotent death, exactly-once `enemy_killed` score
  payload, knockback seam, tinting via config.
- **Basic enemy archetype**: `basic_enemy.tscn` + `data/enemies/basic_enemy.tres`
  (`archetype_id = "basic"`, "Grunt").
- Enemy **feedback** (hit flash, death sink/fade, recolour) and **audio** wrappers.
- **GameRoot combat scoring**: on `enemy_killed` updates kills/combo/score/currency
  with score-multiplier from upgrades, emits `score_changed` / `currency_changed` /
  `combo_changed` exactly once per kill.
- Reused `HealthComponent` for enemies (damage, invulnerability, death).
- Deterministic **combat integration tests** in `tests/run_tests.gd` (damage,
  invalid payload rejection, invulnerability, heal cap, single death, arc query).
- CI: `publish-release` job builds + uploads the APK to a GitHub Release on tag/manual
  dispatch; `scripts/build_android.sh` supports `BUILD_TYPE=debug|release`.

### Verification status (Phase 2)
- GDScript static lint (`gdlint`): **passes** for scripts + tests.
- `.tscn`/`.tres` structural validation: **passes** (10 scene/resource files).
- Cross-reference audit: **clean**.
- Headless test execution + Android APK export: still **not runnable in the authoring
  sandbox** (no Godot/Android toolchain); wired into CI + build script for a real
  runner/local machine.

## [0.1.0] — Phase 1 · Foundation

Working title: **Last Stand: Arena**.

### Added (Phase 1)
- Godot 4.4 project configuration: `project.godot` with mobile renderer, landscape
  display/orientation, physics layers, and keyboard/controller InputMap actions.
- Canonical autoloads registered: `GameRoot`, `EventBus`, `AudioManager`,
  `SaveManager`, `SceneRouter`, `ContentRegistry`, `RunAnalytics`, `TestHarness`.
- Canonical main scene tree (`scenes/main/main.tscn`) + composition controller that
  builds/tears down the gameplay world.
- GameRoot state machine with documented legal transitions and a narrow command API.
- EventBus cross-system signal contract (per design).
- Content registry foundation with typed enemy/upgrade/arena/camera/weapon/audio data
  discovery + validation; default arena + camera `.tres` shipped.
- Player: CharacterBody3D movement (character controller), health component,
  attack/targeting/progression/feedback/audio components, stable command interface.
- Camera rig: data-driven profile follow camera with clip guard + bounded shake.
- Arena scene with floor/walls/collision, player-start + grouped enemy spawn markers,
  pickup points, lighting + environment.
- Basic UI shell: main menu, HUD (health/score/wave/combo/currency), pause, game over,
  settings, upgrade placeholder; floating virtual joystick + attack/dodge buttons;
  localization-ready text lookup.
- Save system: versioned schema v2, pure `normalize_save`, migration hooks, corruption
  recovery, backup + debounced atomic writes.
- Local-only run analytics.
- Headless test runner (`tests/run_tests.gd`) + unit suites (save, combat payloads,
  content validation, scoring) + test doubles (FakeClock, FakeSaveStorage).
- `TestHarness` smoke-test interface.
- Validation tooling (`tool/validate_resources.py`), build script
  (`scripts/build_android.sh`), asset downloader (`scripts/download_assets.py`),
  Android export preset, GitHub Actions `android.yml` CI.
- Documentation: README, `docs/BUILD.md`, `docs/ART_STYLE.md`, `docs/EXTENDING.md`,
  `THIRD_PARTY_ASSETS.md`, `AUDIO_MANIFEST.md`, `gdlintrc`.

### Not yet implemented (later phases)
- Combat/hitboxes, enemy AI + states, spawn manager, procedural waves (Phases 2–3).
- Enemy archetype scenes/data, run upgrade/selection loop, full scoring/combo wiring
  (Phase 4).
- Full audio assets, VFX, menus polish (Phase 5).
- Content unlocks, run summary polish (Phase 6).
- Optimization/pooling/profile + verified Android export + CI green on a real runner
  (Phases 7–8).

### Verification status (Phase 1)
- GDScript static lint (`gdlint`): **passes** (scripts + tests).
- Hand-authored `.tscn`/`.tres` structural validation (`tool/validate_resources.py`):
  **passes**.
- Headless unit tests + Android APK export: **not run in the authoring sandbox** (no
  Godot/Android toolchain available); wired into `.github/workflows/android.yml` and
  `scripts/build_android.sh` for execution on a real runner / locally. See the
  "known limitation" note in the Phase 1 commit message.

### Post-merge fix (UI/UX polish branch)

- `scripts/audio/audio_asset_integrator.gd`: `random_volume_db` is not a Godot 4
  property on `AudioStreamRandomizer`; the assignment raised a runtime
  `SCRIPT ERROR` on every SFX pool build. Renamed to the real property
  `random_volume_offset_db` (same intent: +/-3 dB per-playback variation).
  Caught by the headless UI validation gate added on this branch.
