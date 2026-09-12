# Manual Code-Quality and Bug Audit — 2026-09-12

Scope: manual review across campaign composition, world/geometry, encounters, persistence, routing, events, UI, combat-facing integration, resources, tests, and repository structure. This is a source audit, not proof from Android hardware. Findings are classified as **bug**, **high-confidence defect risk**, or **maintainability/performance debt** so speculation is not presented as a reproduced crash.

## Executive summary

The repository has unusually strong static gates and regression coverage: 1,138 Python tests pass, 175 Godot resources validate, assets validate, and the typed-architecture, engine-API, guard, scene-path, format, and signal gates pass. The best parts are defensive numeric handling, explicit collision layers, versioned save normalization, and broad contract testing.

The main weakness is a split architecture. Most core systems are strongly typed and resource-driven, while the shipping campaign crosses boundaries through large mutable `Dictionary` graphs. Many campaign functions assume validation has already made every key and type safe. That produces compact authoring code, but weakens refactor safety exactly on the default game path. Large manager classes and global EventBus coupling further increase the change radius.

## Bugs and defect risks

### 1. SceneRouter reports success without checking Godot's result — bug

**Evidence:** `scripts/core/scene_router.gd:38-40`

`SceneTree.change_scene_to_file()` returns an `Error`, but the return value is discarded and the wrapper always returns `true`. `ResourceLoader.exists()` only proves that a path exists; it does not prove that the scene loads or instantiates. A corrupt/import-failed scene therefore appears successful to callers, `_last_error` is not updated, and no failure diagnostic is emitted.

**Fix:** capture the error, clear `_transitioning`, set `_last_error`, report it, and return `false` when the result is not `OK`.

### 2. Scene transition lock covers only one frame — high-confidence race risk

**Evidence:** `scripts/core/scene_router.gd:36-46`

The comment says the flag wraps transition completion, but `_reset_later()` waits for only one process frame. Scene replacement/import can take longer than one frame. A second route request can then be accepted while the first transition is still settling.

**Fix:** use a completion signal/known scene-tree state rather than a one-frame delay, or keep the lock until `current_scene` changes to the expected instance.

### 3. Campaign construction has non-transactional early returns — bug-prone failure path

**Evidence:** `scripts/campaign/campaign_game.gd:40-77`

`build_world()` mutates the tree in stages and returns early on world-build or player-instantiation failure. It does not locally roll back the partially created world/support nodes. `GameRoot` eventually notices a missing active player and enters ERROR, but the failed graph remains allocated and attached until another path calls `_clear_world()`.

**Fix:** build beneath a detached staging root, validate every required object, then attach/commit; otherwise free staging immediately. Return `bool` from the builder instead of inferring success from the active-player side effect.

### 4. Required encounter actor can be suppressed under the player — gameplay soft-lock risk

**Evidence:** `scripts/campaign/campaign_encounters.gd:60-76`

A required enemy does not spawn while the player is within 8 m of its authored position. This avoids pop-in on the player, but there is no alternate safe spawn position. A player standing on or circling a mission guard marker can see an objective requiring a hostile that does not exist. Moving away resolves it, so this is a recoverable soft lock rather than permanent save corruption.

**Fix:** project a nearby safe/nav-walkable spawn point outside the exclusion radius and spawn there; communicate temporary suppression to objective routing.

### 5. Encounter activation tests member points instead of encounter center — inconsistent authored semantics

**Evidence:** `scripts/campaign/campaign_encounters.gd:60-65`; campaign JSON includes each encounter's `center`.

The JSON authors `center` and `activate_radius`, but runtime activation ignores `center` and activates when close to any member. Spread-out encounters therefore have a larger, irregular activation union than the authored circle suggests. The data field and runtime meaning disagree.

**Fix:** use `group.center` as the activation origin, or remove/rename the unused field and validate the actual semantics.

### 6. Navigation flow field is rebuilt every streaming tick while any enemy is active — performance defect

**Evidence:** `scripts/campaign/campaign_encounters.gd:33-40,57-58`

Every 0.3 seconds, any non-empty active set triggers a full flow-field rebuild, even if the player remains in the same navigation cell and no actor spawned/despawned. On mobile this creates avoidable periodic CPU spikes.

**Fix:** cache player nav cell and obstacle revision; rebuild only when either changes. The `_spawn()` path already performs another rebuild, making the same tick potentially rebuild twice.

### 7. Checkpoint state advances before persistence succeeds — behavior/save mismatch

**Evidence:** `scripts/campaign/campaign_director.gd` `_visit_checkpoint()`

The in-memory checkpoint is assigned and healing is granted before `save_progress(true)` succeeds. On failure, the director continues treating the new checkpoint as current while disk still contains the old one. The message mentions save failure, but `_checkpoint_inside` prevents an immediate retry until the player exits and re-enters the radius.

**Fix:** stage the checkpoint, persist it, then commit `_checkpoint_inside`; alternatively retain a dirty retry state and retry automatically.

### 8. Mission mutation and rewards are not a genuinely atomic transaction — save consistency risk

**Evidence:** `scripts/campaign/campaign_director.gd:197-236`

The comment promises one atomic save, but mission state, upgrades, weapon, XP, campaign snapshot, and meta credits are mutated through several systems and callbacks. Save failure does not roll back any runtime mutation. A later successful save probably reconciles it, but process death between failed persistence and retry can produce a partially old profile.

**Fix:** construct one normalized transaction snapshot containing campaign and wallet/build changes, then commit once through SaveManager; surface and retain a retryable transaction on failure.

### 9. Completion retry logic invokes completion even when it knows state is not playable — confusing control flow

**Evidence:** `scripts/campaign/campaign_director.gd:219-223`

When state is not PLAYING, `_completion_pending` is set, but `GameRoot.complete_campaign()` is still called unconditionally. `GameRoot` silently ignores it outside PLAYING, and physics later retries it. Current behavior works only because another class's guard absorbs the invalid call.

**Fix:** call immediately only in PLAYING; otherwise set the pending flag. This makes the local control flow correct rather than relying on a remote no-op.

### 10. Save backup rotation happens before the new primary commit — durability tradeoff

**Evidence:** `scripts/save/save_manager.gd:303-323`

All backup generations are rotated before writing the new primary. If backup rotation succeeds and primary commit fails, the primary remains valid, but backup history has already changed. Repeated write failures can collapse useful historical diversity even though no new valid primary was created.

**Fix:** write and verify the new temp first; rotate backups immediately before an atomic replacement, or rotate only after successful primary commit using a copy of the old primary held in a separate temporary file.

### 11. Temporary save file is left behind after rename failure — cleanup bug

**Evidence:** `scripts/save/save_manager.gd:477-498`

The temporary file is removed on buffered-write failure, but not when `rename_absolute()` fails. It can remain indefinitely and be overwritten on later attempts. This is not profile loss, but it is stale-file leakage and loses a useful explicit recovery path.

**Fix:** either remove it after logging or preserve it under a documented recovery name and consider it during load.

### 12. JsonHelpers accepts negative file length anomalies — defensive gap

**Evidence:** `scripts/utilities/json_helpers.gd:34-46`

The size check rejects only `length > MAX_FILE_BYTES`; it does not reject a negative/error length before `get_as_text()`. Godot normally returns a valid non-negative length for an open file, so this is low probability, but the helper claims total/unreadable-safe behavior.

**Fix:** reject `length < 0` as well.

### 13. Campaign boundary uses mutable untyped dictionaries — systemic runtime risk

**Evidence:** `scripts/campaign/campaign_definition.gd`, `campaign_director.gd`, `campaign_world.gd`, and `campaign_encounters.gd`

The campaign passes sectors, interactions, encounter groups, rewards, and progress as mutable `Dictionary` values and frequently uses property syntax (`sector.id`, `member.at`). This conflicts with the repository's documented “no Dictionary state channels” architecture. Validation protects initial JSON, but mutation and refactors remain string-key/runtime-typed.

**Fix:** parse once into typed `RefCounted`/`Resource` records (`CampaignSector`, `CampaignEncounter`, `CampaignMember`, `CampaignMission`, `CampaignProgressState`) and expose read-only typed arrays.

### 14. Campaign progress object is shared by reference across systems — hidden coupling

**Evidence:** `CampaignDirector.configure()` passes its mutable `progress` dictionary directly to `CampaignEncounters.configure()`.

Encounters mutates `progress.defeated`; director assumes those mutations are immediately visible and persists later through callbacks. There is no ownership boundary, making ordering and future asynchronous changes dangerous.

**Fix:** director should own progress mutation. Encounters should emit typed defeat events; director updates and persists state.

### 15. PBR module extraction assumes shallow scene topology — asset-wiring fragility

**Evidence:** `scripts/campaign/campaign_geometry.gd` `_module_mesh()`

The helper checks only the instantiated root and its direct children for `MeshInstance3D`. A harmless asset re-export that introduces another transform node makes extraction fail and silently falls back to boxes. Asset validation still passes because the scene itself remains valid.

**Fix:** use a small typed recursive traversal, validate exactly one intended mesh, and emit a diagnostic when fallback occurs.

### 16. Merged perimeter walls receive one style based on their center — visible theme mismatch

**Evidence:** `CampaignGeometry.perimeter()` merges long collinear edges; `CampaignWorld.build()` calls `_wall_style_at(wall.get_center())` once per merged AABB.

A merged wall spanning district boundaries gets the theme of whichever sector is nearest its midpoint. Military/hazard/tech/rusted transitions can therefore occur in the wrong district or fail to occur at all.

**Fix:** split perimeter runs at sector/theme boundaries, then batch each themed segment independently.

### 17. Wall assets are non-uniformly stretched to collision AABBs — visual quality risk

**Evidence:** `CampaignGeometry.wall_batch()` scales authored 1.00 × 0.27 × 0.05 modules to approximately 8.0 × 1.8 × 0.7.

This scales panel detail vertically by ~6.7 and thickness by ~14, distorting bevels, emissive strips, normals, and apparent texel density. It technically wires the asset but does not preserve its authored proportions.

**Fix:** compose vertically/proportionally sized wall modules or author campaign-scale variants; keep a thin independent collision volume instead of forcing render mesh to match collision thickness.

### 18. Ground texture/detail density changes by an 8× transform — visible repetition/stretch concern

**Evidence:** `CampaignGeometry.floor_batch()` scales each 1 m mesh to an 8 m gameplay cell.

The model's UVs scale with the mesh, so one authored tile texture spans 8 m rather than repeating every metre. This can make tread/hex details oversized compared with props and characters.

**Fix:** instance 1 m render tiles while retaining 8 m logical/nav cells, or use a material with UV1 triplanar/repeat scaling appropriate to world units.

## Code-quality observations

### Strengths

1. **Excellent automated contract coverage.** Resource paths, scene paths, signals, engine APIs, string formats, and guards have dedicated checks.
2. **Strong finite-number discipline.** Physics and camera code visibly defends against NaN/INF propagation.
3. **Save recovery is thoughtfully engineered.** Normalization, integrity envelopes, size limits, multiple backups, explicit flush, and same-directory rename are substantially better than typical small-game persistence.
4. **Collision and ownership intent is documented.** Comments generally explain why a guard or lifecycle decision exists.
5. **Data assets are organized and licensed.** Texture channels, GLBs, environment variants, manifests, and third-party attribution are easy to locate.

### Weaknesses

1. **God objects remain.** `enemy_base.gd` (~33 KB), `arena_decorator.gd` (~29 KB), `camera_rig.gd` (~27 KB), `effect_director.gd` (~26 KB), `game_root.gd` (~25 KB), and `player.gd` (~25 KB) are large enough that local changes require broad context.
2. **The shipping campaign bypasses the strongest architecture rule.** Typed resources are used heavily elsewhere, but the campaign's most important domain model is dictionary-based.
3. **Global EventBus usage is excessive.** It is useful for telemetry/UI/audio, but several gameplay state changes are globally broadcast where direct typed ownership would be clearer. The code even provides `EventBus.bind()`, yet many subscribers use direct `connect()`.
4. **Comments sometimes overclaim guarantees.** Examples include SceneRouter calling a one-frame wait “completion” and campaign rewards calling a multi-owner mutation sequence “atomic.” Comments should describe proven behavior, not intent.
5. **Tests are broad but mostly static/textual.** Passing Python tests cannot reproduce frame-order, imported-scene topology, GPU material appearance, Android filesystem behavior, or touch lifecycle races. The repository documentation acknowledges this, but confidence should remain calibrated.
6. **Magic dimensions and IDs are scattered.** `176.0`, `8.0`, `0.27`, `0.05`, district IDs, style IDs, and interaction kinds are repeated across files instead of belonging to typed configuration/enums.
7. **Fallbacks can hide regressions.** Geometry silently falling back to boxes keeps the game runnable but lets a visual regression ship unnoticed. Production fallback should emit one actionable diagnostic.

## Recommended order of work

1. Fix SceneRouter result handling and transition completion tracking.
2. Make campaign world construction transactional with a typed boolean/result.
3. Replace campaign Dictionary domain objects and shared mutable progress with typed records and director-owned mutations.
4. Cache navigation rebuilds by nav cell/revision and provide safe alternate encounter spawn points.
5. Make checkpoint/mission/meta persistence a single retryable SaveManager transaction.
6. Correct campaign environment scale/UV density and split perimeter styles at district boundaries.
7. Add runtime Godot tests that instantiate Station Zero, assert imported meshes (not fallback boxes), traverse every objective, simulate save-write failures, and perform repeated pause/map/checkpoint transitions.
8. Run an Android device soak for thermal performance, touch ownership, app-background save behavior, and filesystem rename behavior.

## Remediation status

The actionable runtime defects identified in this review were remediated in the same branch:

- Scene routing now checks the engine `Error`, tracks actual scene replacement, and has a bounded timeout.
- Failed campaign construction now reports and rolls back partial world graphs.
- Encounters activate from authored centers, choose alternate walkable spawn points, and rebuild flow fields only after nav-cell changes.
- Failed checkpoint writes roll back the in-memory checkpoint and remain immediately retryable.
- Campaign completion no longer makes a knowingly invalid state call.
- Failed save renames clean their temporary file; JSON reads reject invalid negative lengths.
- Environment mesh discovery is recursive and emits a fallback diagnostic.
- Perimeter render geometry is split by module before theme selection, wall render thickness is no longer collision-stretched, and floor PBR UVs repeat at world scale.

Items 8, 10, 13, and 14 describe broader transaction/typing architecture rather than isolated safe patches. The immediate failure modes around them were hardened, but fully replacing campaign dictionaries and introducing a cross-store transaction object is a larger schema/API migration and remains architectural follow-up rather than being disguised as a small bug fix.

## Validation run during this review

- `python3 -m unittest discover -s tests/python -p 'test_*.py'`: **1,138 passed** (Android SDK/ADB execution unavailable; checklist path reported not tested as designed).
- `tool/validate_resources.py`: **175 files valid**.
- `tool/validate_assets.py`: **assets valid**.
- Guard, typed-architecture, engine-API, scene-path, string-format, and signal gates: **passed**.

These results are evidence of strong static hygiene, not evidence that the runtime findings above are impossible.
