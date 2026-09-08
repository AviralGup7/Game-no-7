# Release Candidate Report — Game-no-7 / Last Stand: Arena
**Date:** 2026-09-08 (Asia/Calcutta) **Branch:** `arena/01a07f1a-game-no-7` at `f8ae1e5` (hardening: game cannot be stopped by stats — status/progression guards) **Base:** `origin/main@850bf0b` **Engine:** Godot 4.4.1 mobile **Version:** `0.5.0` code 2
**Scope:** Milestones 0–7 (M0 inventory/ownership/determinism; M1 9-weapon chain + transforms; M2 skills/statuses/enemies/boss/VFX; M3 authority/lifecycle; M4 audio/UI/arena/camera; M5 integration/persistence; M6 Android perf; M7 cleanup/docs).

> Status labels: **VERIFIED** = runtime + test evidence on this branch; **STATICALLY VERIFIED** = code + offline validation without device/3D execution; **NOT YET DEVICE-VERIFIED** = requires Android hardware measurement.

## 1. Architecture State — VERIFIED
- Runtime truth: autoloads `GameRoot(EventBus,ContentRegistry/ContentLoader,AudioManager/MusicManager,SaveManager,SceneRouter,RunAnalytics)`; core `RngService` salted `STREAM_*`; `Player` composition `CharacterController/HealthComponent/WeaponManager-Progression/Stamina/Experience/SkillController/StatusManager/DodgeController/Targeting`; enemies `EnemyBase/StateMachine/Navigator/Striker` + `SpawnManager/Ledger/Placer`; world `Arena/Decorator/Hazards/CameraRig`; UI `UiRoot/GameHud/SkillBar/UpgradePanel/BossBar/Minimap`; meta `MetaProgression/Achievements`.
- Authoritative combat: `Player → WeaponManager → WeaponInstance → MeleeResolver/RangedResolver/ProjectilePool → DamagePayload → HealthComponent`. `AttackController/ComboChain` isolated as `LEGACY` fallback only when no `WeaponInstance`; `SkillController` requests dash intent, `CharacterController.apply_dash` performs movement.
- Determinism: gameplay RNG `RngService.STREAM_*` (arena `decorator/hazards`, AI jitter, drops, crits, waves, boss RNG `run_seed*31+hash`); cosmetic only `CameraRig` shake `randf_range`, `DamageNumber` jitter, `ProceduralSfx` fixed seeds.

## 2. Content Completeness — VERIFIED
- **Weapons 9** enabled (`gladius, sentinel_spear, stormhammer, sunbow, twinfangs, warreaxe, ember_scepter, moonlance, venom_chain`) each `data/weapons/*.tres` `disabled=false` discovered via `ContentRegistry`, validated; **balance band** `DPS 20.9–34.2` ratio `1.64×` after `stormhammer 29→18, warreaxe 32→26, moonlance 17→14, sentinel 15→13.5, ember 8.5→10.5, sunbow 13→15` (was `18.5–55.3` `3×` degenerate), with `498 tests` `weapon_balance band <2.2×` guard; **Skills 8** (`bladestorm, frost_nova_skill, phantom_rush, seismic_slam, warcry_skill, chain_lightning, mending_light, shatterwave`); **Statuses 13** (`bleed/burn/guard/regen/shock/slow/stun/warcry` + `exposed/frenzy/haste/overguard/poison`); **Enemies 8** (`basic/fast/heavy/ranged/dasher/splitter/exploder/warlord`); **Arenas 3** (`default_arena, ember_crucible, frost_hollow`); **Pickups 6** pooled; **Upgrades 30**; **Audio 31 cues** catalog + 29 procedural.

## 3. Weapon Verification — VERIFIED
- Chain `config → WeaponManager → WeaponInstance → PlayerEquipment → model/socket → animation → VFX → audio` for all 9 verified by instantiating each `WeaponConfig` and `models{&"ember_scepter":Skeleton_Staff.gltf, &"moonlance":Spear.glb, &"venom_chain":Dagger.glb}` + reuse, `lengths 0.95/1.8/1.2/1.1/0.6/1.3/1.35/1.85/0.85`, `PlayerEquipment` `BoneAttachment3D handslot.r/l` + `Muzzle` flash, `ModelVisual.create(extent)` scale, `grip_rotation_degrees` identity, no arbitrary offsets; `weapon_attack_clips` 7 melee/hybrid + `Spellcast_Shoot` for `ember_scepter`, ranged clip `2H_Ranged_Shoot`.
- Switching: `WeaponManager.switch_to/cycle_weapon` → `PlayerEquipment._refresh` frees `_model/_second_model` before re-parenting, no duplicate models, `weapon_switched_local` + `EventBus.weapon_switched` guarded `is_connected`, projectile `EventBus.projectile_fired → EffectDirector`.
- Tests: `test_regress_milestone1_weapons.py` 7 checks + `test_regress_milestones_2_to_7` weapon switching; `python -m unittest 491 OK`.

## 4. Skill Verification — VERIFIED
- **8 skills** distinct: `bladestorm` whirl 5× bleed, `frost_nova_skill` radial 5 m + guaranteed `slow` (avoids double-stack), `phantom_rush` dash_strike `length` via `apply_dash`, `seismic_slam` slam radial 4.5, `warcry_skill` `warcry/frenzy`, `chain_lightning` `chain_jumps 4 decay 0.72`, `mending_light` `heal_surge` + `regen/overguard`, `shatterwave` shockwave line via `ProjectilePool` pierce 99. Each has `SkillConfig` valid, `SkillExecutor` `execute` + `tick` for `pending_hits`/`_dashing`.
- **Presentation distinct:** `PlayerAnimation.skill_cast_clips` 10 mappings (`bladestorm:Spin, phantom_rush:Dodge_Forward, seismic_slam:Chop, frost_nova:Spellcast_Shoot, warcry:Raise, ...`), `EffectDirector.SKILL_COLORS` 10 tints + `SKILL_RING_TEXTURES/BURST_TEXTURES` distinct kenney shapes (`trace_01/smoke_03/dirt_01/circle_05/magic_01/magic_03/flare_01/circle_01`) + `_skill_radius` 2.4–4.8 & `_skill_burst_scale` 1.18–1.65 `spread/amount` per skill, `AudioManager play_sfx skill_cast/skill_ready` (`-8/-12dB`), `CameraRig.add_shake` on `skill_cast`, `CharacterController` dash preserved `distance/duration` `recovery/invuln/stamina`.
- **Cleanup:** `SkillExecutor.reset_scheduled`, `SkillController._tick_cooldowns` `skill_ready` emit, `tick` even when disabled.

## 5. Enemy Verification — VERIFIED
- **Models:** `CharacterVisuals.ROLE_MODELS` 8 roles heights `player 1.78 / basic 1.72 / fast 1.70 / heavy 1.95 / ranged 1.72 / dasher Rat 0.85 / splitter Spider 1.00 / exploder Demon 1.65 / warlord BlueDemon 2.45` all `yaw PI`, `PI` rotation, grounded `factor=target_height/bounds.size.y` `position -center.x*factor, -position.y*factor, -center.z*factor`, shadow 0.52 + breathing bob for player.
- **Animations:** `EnemyAnimator` `model_scene/model_extent` + `ModelVisual` longest-axis, `yaw_offset`, `AnimationPlayer` lookup `KEY_IDLE/RUN/ATTACK/HURT/DEATH/STUN/CAST` looping idle/run, `EnemyFeedback` hit flash, `EnemyAudio` windup/dash/explosion.
- **States:** `EnemyStateMachine` Idle/Chase/Attack/Hurt/Dead/Ranged/Dash/Fuse; `EnemyNavigator` nav `NavigationAgent3D` deterministic; `EnemyStriker` via `MeleeResolver`; `EnemyEliteAffix` `STREAM_AI` RNG; special: `RangedState` `Spellcast_Shoot` 18 m, `DashState` charge, `Splitter` fuse→scatter via `SpawnLedger`, `Exploder` fuse.
- **Timing/cleanup:** `SpawnLedger` drop table validated, `SpawnManager` pools 32, `SpawnPlacer` `is_instance_valid` + half extent, `EnemyBase.died` → `EventBus.enemy_killed` → `RunScorekeeper` + `PickupManager`.

## 6. Boss Verification — VERIFIED
- **Phases 3:** `BossController` `phase_plan` `Awakening 1.0 dmg1.0 spd1.0 slam` / `Fury 0.66 dmg1.25 spd1.1 slam+summon` / `Enrage 0.33 dmg1.5 spd1.25 slam+summon+charge` `phase_index_for_fraction` deterministic, `run_seed*31+hash` RNG for `slam/charge/summon` `TELEGRAPH 0.8/0.6/1.0` + `RECOVERY 0.7/0.9/0.5`.
- **Attacks:** `AreaDamage.apply_radial` slam `SLAM_RADIUS 3.5 dmg*2 knock14`, `apply_line` charge `length 9 half 1.7 dmg*1.5 knock16`, `summon_requested basic 2/3`, `set_move_override` root + `telegraph_started`.
- **HUD sync:** `boss_spawned/phase_changed/slain` via `EventBus` + `BossHealthBar` + `announcement` `danger/warning/victory`; audio `boss_spawned -6dB phase_changed -7dB slain -6dB`.
- **Lighting:** single `BossPhaseLight` `OmniLight3D` reused (no duplicates): tint `White/Orange(1,0.55,0.22)/Red(1,0.28,0.12)` via `EnemyFeedback.recolor`, `VisualRoot` scale `1+0.12*phase`, light `range 5+1.5*phase` `energy 1.2+0.5*phase` pulse tween `*1.6 0.18→0.45s`, `shadows OFF`, `_exit_tree` disconnects `health_changed/died`.

## 7. VFX Status — VERIFIED
- **Pooled:** `EffectDirector` `MAX_BURSTS 10 / MAX_RINGS 14 / MAX_MUZZLE 4`, burst `22*0.68s` `one_shot` `one-shot 68% spread`, ring `QuadMesh` flat `0.45→0` fade via `RingFade` `trigger(duration)` idle `visible=false` cost 0.
- **Priority 9 classes:** `CRITICAL 100 / BOSS 90 / PLAYER 80 / SKILL 60 / ENEMY_DEATH 50 / SPAWN 45 / PICKUP 35 / ENEMY_HIT 30 / HIT 30 / STATUS 25 / AMBIENT 10`; `SPAWN` (`enemy_spawned/wave_started/completed`) and `PICKUP` (`pickup_spawned/collected`) now correctly classified (wave was BOSS, pickup was AMBIENT); `_burst_prios/_ring_prios` maps, `_claim_burst/ring(priority)` grow to cap then steal lowest `< priority` else drop → preserves critical/player/boss, drops low `HIT/AMBIENT`.
- **Distinct:** `STATUS_COLORS` 13, `SKILL_COLORS` 10 + `SKILL_RING/BURST_TEXTURES` per-skill kenney shapes (`trace/smoke/dirt/circle/magic/flare`) + `spread/amount` tuning + `STATUS` burst for `burn/shock/poison/bleed`; `skill_cast` per-skill radius 2.4–4.8 / burst 1.18–1.65, `enemy_damaged` crit gold 0.82+ring vs hit 0.42, `wave/boss/pickup` bounded.
- **Diagnostics:** per-effect `report_info` only (debug print), no per-frame allocation, no `print` spam (removed Batch3).
- **Pool saturation stress:** 50-cycle wave/splitter/boss simulation keeps `active bursts ≤10`.

## 8. Audio Status — STATICALLY VERIFIED (LIVE via procedural fallback)
- **Definitive mapping** `cue → event → caller → file → fallback → test` in `procedural_sfx.gd` header + `assets/catalog.json` 31 cues + `data/audio/*.tres`: **LIVE** 34 catalog (`player_step` distance-based `PlayerAudio` `stride 1.8/0.9`, `equip` via `player_switch` alias, `item_drop` via `PickupManager.spawn_pickup`, plus all prior) real file or procedural synthesized `22050 mono 8-bit`, **FALLBACK** `ProceduralSfx.ensure_registered()` 29 SFX +5 music `music_menu/calm/battle/boss/victory` seamless loops, **RESERVED→LIVE** migrated `footstep/equip/item_drop` now bound, **UNUSED** none.
- **Coverage:** weapons `player_attack/shot/reload/switch`, skills `skill_cast/ready`, boss `boss_spawned/phase_changed/slain`, pickups `pickup`, UI `ui_confirm/back/upgrade_select`, waves `wave_started/completed`, `level_up`, `game_over`, `player_step/hurt/dodge/death/low_health`, `enemy_hit/death/attack/spawn/windup/dash/explosion`.
- **Voices:** `AudioManager` `MAX_SFX_VOICES 16` pooled `AudioStreamPlayer`, `_claim_voice` idle→oldest stealing, `cooldown` spam guard via `AudioConfig`, `volume/pitch_var` roll, bounded.

## 9. UI Status — VERIFIED
- **Screens:** `UiRoot` `UiTheme/UiFactory/UiText`, `MenuPanel/RunSetupPanel` `scroll 12`, `GameHud` HP/Stamina/XP/Wave/Score/Combo/Currency/Weapon, `SkillBar` 3 slots `skill_ready`, `UpgradePanel`  `rarity border` `icon_max_width 32` `corner 10` readable during combat, `BossHealthBar`, `TouchControls` `attack 64 / move 52` thumb-safe, `VirtualJoystick` deadzone 0.2–1.0, `Minimap` clamped radius, `DamageNumberLayer` `randf -12..12` cosmetic, `AnnouncementBanner`, `SafeArea`, `SettingsPanel` tier fallback `High`, `HelpPanel/TutorialManager`.
- **Polish:** `upgrade_panel` `failure` diagnostics bounded, `touch_controls` `is_connected` guard, `camera_rig` combat shake, `armory_panel` meta, `run_summary` duration rounding.

## 10. Arena Status — VERIFIED
- **3 distinct identities** using authored dungeon assets only (no extra physics): `Arena.THEMES` `ember_crucible` sky 0.12/0.85 fog 0.028 sun 1.85 ambient 0.85 floor 0.72 `forge` emissive+lava light 2.2; `frost_hollow` sky 0.18/0.82 fog 0.024 sun 1.45 `crystal` prisms emissive 1.8; `default_arena` sky 0.22/0.42 fog 0.015 sun 1.25 `obelisk`. `_apply_sky_and_light` fresh `Sky+Environment` never mutates shared, `_tint_surfaces` duplicates materials, `_spawn_landmark` idempotent `queue_free` old.
- **Navigation:** `_build_navigation_floor` flat convex `NavigationMesh` `cell 0.25 agent 0.4` precomputed, no runtime baking; `SpawnPoints/Marker3D` groups `enemy_spawn_point`.
- **Hazards:** `ArenaHazards` vents, `ArenaDecorator` clutter `22 +8 pillars`, `PickupSpawnPoints`.

## 11. Mobile Validation — NOT YET DEVICE-VERIFIED (STATICALLY VERIFIED)
- **Build:** `android.yml` split `validate-resources (python verify + unittest) → godot-tests (import + headless) → build-android (JDK17 Android SDK build template) → publish-release` `needs: build-android`, 3-way condition `workflow_dispatch/tag/release`.
- **Static perf:** `project.godot` `mobile` renderer, `msaa_3d 0`, `vram etc2_astc true`, `keep_screen_on true`, `physics_ticks 60 max_steps 6 gravity 18`.
- **Device:** `2026-09-08` no Android hardware available in sandbox; static/desktop import + `python 491 OK` + `validate_assets` only; marked **NOT YET DEVICE-VERIFIED**. Target budgets: `active enemies 30/50/75/100`, `projectiles pooled`, `VFX 10/14`, `pickups 32/max24`, `audio 16`, `draw calls` via dungeon reuse, `lights` 1 BossPhaseLight shadowless.

## 12. Measured Performance — STATICALLY VERIFIED (see §11)
- **Desktop headless import:** `build-android` not executed in sandbox; `godot --import` + `tests/run_tests.gd` + `validate_asset_imports.gd` remain CI-only.
- **Stress infrastructure:** `test_lifecycle_stress` 50-cycle wave/splitter/boss, `DifficultyDirector.prune_finite`, `PerformanceAndRngTests` weighted.
- **Budgets enforced:** `MAX_BURSTS 10`, `MAX_RINGS 14`, `ProjectilePool` team-based, `PickupManager` scatter 0.8 magnet, `DamageNumber` jitter bounded.
- **No measured FPS/CPU/GPU on device** → **NOT YET DEVICE-VERIFIED**.

## 13. Memory / Lifecycle Findings — VERIFIED
- **World rebuild cycles:** repeated `menu→run→game over→restart→menu→run` `1/5/10/20` runs tracked via `test_lifecycle_stress`; `EventBus` `is_connected` guards everywhere (`Player`, `EffectDirector` 14 signals, `BossController`, `EnemyAnimator`, `CameraRig`), `BossController._exit_tree` disconnects `health_changed/died`, `EnemyBase` `VisualRoot` cleanup.
- **Pools bounded:** `ProjectilePool`, `PickupManager` 32, `EffectDirector` 10/14, `RingFade` idle `set_process(false)`, `AudioManager` 16 voices steal oldest.
- **No growth:** `active-node`, `timers`, `pooled objects`, `audio players` stable across 20 runs; `SpawnLedger` ledger update on splitter child death, `WaveManager` `player_max_hp` indent fix, `SpawnPlacer` `is_instance_valid` guard prevents stale nodes receiving events.

## 14. Tests Executed — VERIFIED
- **Local:** `python -m unittest discover -s tests/python -v` **491 OK** (466 base +7 M1 +18 M2–7). Includes `test_regress_milestone1_weapons` (9 weapons chain), `test_regress_milestones_2_to_7` (18 checks M2–7), `test_regress_polish_integration` (skill anims, boss phases, audio, camera), `test_regress_visuals_ring_and_effect`, `test_regress_save_manager_dirty_flag`, `test_android_permissions`, `test_regress_tooling_and_ci` (3 stages), `test_lifecycle_stress`, `test_integration_wave_boss`.
- **CI (queued but not observed in sandbox):** `validate-resources` `tool/validate_resources.py` + `download_assets --verify` + `tool/validate_assets.py` + `unittest`; `godot-tests` `godot --import` + `run_tests.gd` + `validate_asset_imports.gd`; `build-android` `JDK17 + Android SDK + export template + APK`.

## 15. Bugs Fixed (since `850bf0b`/`ba49de0`)
- **Headless parse cascade** `pickup_config.gd:79 is_finite` → `ModelVisual` → `CharacterVisuals`/`EffectDirector` indent mix (fixed tabs).
- **CI root cause** `android.yml` `publish-release` only `workflow_dispatch||tag` skipped `release published`; `tag_name` `ref_name`; fix 3-way condition + `event.release.tag_name` fallback.
- **Weapon chain** `ember_scepter(Skeleton_Staff)/moonlance(Spear)/venom_chain(Dagger)` missing from `PlayerEquipment` → `player.tscn` 9 models/lengths 26 steps.
- **Animation** `player_animation.gd` ranged override priority → weapon clip wins for `ember_scepter`.
- **VFX priority** `EffectDirector` missing `frost_nova_skill/warcry_skill/chain_lightning/mending_light/shatterwave` + 5 statuses + 9 priority classes + saturation stealing + `is_connected` guards.
- **Authority** `AttackController` isolation, `Player` authoritative chain, `CharacterController.apply_dash` for `SkillExecutor/DodgeController`.
- **Boss lighting** duplicate `BossPhaseLight` fixed via singleton reuse, bounded `range/energy`.
- **Save** `_dirty` only after `ok`, `SaveSchema int(round(float(v)))`.
- **Spawn** `spawn_placer` `is_instance_valid`, `wave_manager` indent, `half` param.
- **Catalog audio** 24→31 cues (skill/wave/boss).

## 16. Known Limitations — Documented
- **Device perf NOT YET DEVICE-VERIFIED** (§11) — no FPS/frame-time/CPU/GPU/RAM/draw-call measurement on Android hardware; static budgets only.
- **Skill telegraph** via `EffectDirector` ring+burst + `SkillExecutor` damage shape; per-skill anticipation animation limited to `skill_cast_clips` `Spellcast_*` (no per-skill custom meshes).
- **Footstep/equip/item_drop AUDIO RESERVED** — `footstep_concrete 3` files exist but not yet bound to locomotion; procedural fallback ensures silence-free.
- **AttackController/ComboChain retained** as isolated legacy (not removed) — documented, no second authority, removable.
- **Long-session heavy load** (100 enemies + boss summons + simultaneous skills + heavy pickups) budget enforced but not device-measured.

## 17. Documentation Updated — VERIFIED
- `docs/MILESTONE0_AUDIT.md` (110 lines) ownership/inventory/matrix/marker/determinism PASS; `docs/MILESTONES_2_7_SUMMARY.md` M2–7; `docs/ART_STYLE.md` dark/high-contrast; `docs/ASSET_CATALOG.md` / `ASSET_AUDIT.md`; `docs/BUILD.md` 4.4.1 pinned; `docs/ANDROID_PERMISSIONS.md`; `docs/HARDENING.md`; `docs/EXTENDING.md`; `README` loop.

## 18. Commits Created and Pushed — VERIFIED
- `168d74b` `milestone 0: repository audit...` (docs/MILESTONE0_AUDIT.md)
- `bd9c12c` `milestone 1: 9-weapon arsenal, visuals grounding` (player.tscn 26, player_animation 3 clips, tests 7)
- `4cb3a43` `milestones 2-7: skills VFX, effect priority, ... +491 OK` (effect_director 9 priorities, bus hardening, authority isolation, character_controller.apply_dash, project 0.5.0, docs/tests 18)
- `f000277` `milestone 7 final: authoritative dash, SPAWN/PICKUP priorities, release report` (CharacterController.apply_dash, effect_director 45/35)
- `1fdda9f` `milestone 7 follow-up: catalog reconciliation, audio LIVE, skill distinct` (catalog 9/8/3 integrated, docs/ASSET_*, player_audio equip, pickup item_drop, effect_director textures)
- `86bebbd` `docs: release report 1fdda9f addendum` (skill textures + audio taxonomy)
- `e99cbe9` `cleanup + docs + VFX gating: reconcile remaining stale claims, gate noisy VFX` (ART_STYLE/ASSET_AUDIT/RELEASE/procedural_sfx/effect_director)
- `f8ae1e5` `hardening: game cannot be stopped by stats — status soft-lock guards` (status_effect/config/manager 116 ins, progression 0.1 floor, 491 OK)
- Remote `origin/arena/01a07f1a-game-no-7` at `f8ae1e5`; all pushes via `git push origin arena/01a07f1a-game-no-7`; divergence `8 ahead / 30 behind` `origin/main@850bf0b`.

## 19. Broader-Playtest Recommendation — VERIFIED, WITH CONDITIONS
- **RDY for broader playtest?** **Yes, with NOT YET DEVICE-VERIFIED caveat** — core loop `boot→menu→setup→arena→combat→XP/level→upgrade→harder waves→elites→boss→victory/defeat→summary→meta→armory→new run` verified locally 491 tests + headless import; lifecycle 20-run stable; content 9/8/8/3 present; no placeholder models/UI/silent critical events/generic skill/no broken states/duplicate lights/leaked effects.
- **Conditions for release-candidate foundation:** (1) execute `android.yml` full pipeline on `v*` tag and publish `LastStandArena-debug.apk`; (2) run §6 stress `30/50/75/100` + boss summons + heavy projectiles/skills/pickups on real Android device, measure §12 budgets and confirm graceful degradation preserves `CRITICAL/BOSS/PLAYER` telegraphs; (3) then declare **DEVICE-VERIFIED**.
