# Milestone 0 — Repository and Current-State Audit (2026-09-08)

**Branch:** `arena/01a07f1a-game-no-7` at HEAD (both pushed).  
**Base:** `origin/main` at `70ada0d`. Divergence: 48 ahead / 3 behind (main at 70ada0d, branch at HEAD). Working tree clean. Working tree clean. No unpushed commits. Tag `v0.5.0` pushed, CI run `34187704091` queued for that tag.

## Repository discipline
- `git status` clean, `origin/arena/01a07f1a-game-no-7` at HEAD, `git ls-remote` confirms same.
- Recent pushes: `edc6697→cd351f7→9baa534→bfe9588→1faec6a→6b4ca67` (6 commits since `ba49de0` baseline). All pushed; no divergence inside branch.
- Workflow `.github/workflows/android.yml` split into `validate-resources` + `godot-tests` → `build-android` → `publish-release` (fixed `release` event handling, tag fallback).

## Architecture ownership (runtime truth)
- **Autoloads:** `GameRoot` (state machine PLAYING→...), `EventBus` (cross-system signals), `ContentRegistry/ContentLoader` (data-driven `.tres`), `AudioManager/MusicManager`, `SaveManager`, `SceneRouter`, `RunAnalytics`, `TestHarness`.
- **Core:** `RngService` (salted streams), `HitstopManager`, `AreaDamage`, `CombatQuery`, `CriticalSystem`.
- **Player:** `Player` + `PlayerLocomotion`/`PlayerBuild` + `CharacterController`, `HealthComponent`, `WeaponManager/WeaponInstance` + `Melee/RangedResolver` + `ProjectilePool`, `SkillController/SkillExecutor`, `StatusManager/StatusEffect`, `DodgeController`, `Stamina/Experience`, `PlayerAnimation/Equipment/Feedback/Audio`.
- **Enemies:** `EnemyBase` + `EnemyLocomotion/Navigator/Striker` + `EnemyStateMachine` (Idle/Chase/Attack/Hurt/Dead/Ranged/Dash/Fuse), `EnemyAnimator/ModelVisual/CharacterVisuals`, `SpawnManager/SpawnLedger/SpawnPlacer/SpawnPatterns`, `BossController/BossPhaseConfig`, `EnemyEliteAffix`, `EnemyFeedback/Audio`.
- **World:** `Arena/ArenaConfig/ArenaDecorator/ArenaHazards`, `CameraRig/CameraProfile`, `Pickup/DropTable/PickupManager`, `WaveManager/WavePlanner/WaveMutators/DifficultyDirector`, `EffectDirector/RingFade`.
- **UI:** `UiRoot` + `UiTheme/UiFactory/UiText`, `GameHud`, `SkillBar`, `UpgradePanel`, `BossHealthBar`, `Minimap`, `DamageNumberLayer`, `TouchControls/VirtualJoystick/TouchActionButton`, `SafeArea`, `SettingsPanel/ArmoryPanel` etc.
- **Meta:** `MetaProgression`, `Achievements`, `DailyChallenge`, `SaveSchema`.

Docs: `README` (loop, principles), `BUILD` (4.4.1 pinned, verify/import), `ART_STYLE`, `ASSET_CATALOG/AUDIT`, `AUDIO_MANIFEST`, `THIRD_PARTY_ASSETS`, `ANDROID_PERMISSIONS`, `EXTENDING`, `HARDENING`.

## Inventory since previous phase (since `850bf0b`/`ba49de0`)
- **Arena:** `THEMES` dramatic (ember 0.12/0.85 fog0.028 sun1.85, frost 0.18/0.82 fog0.024, default) + `_spawn_landmark` forge/crystal/obelisk emissive+light; `arena_decorator` per-arena braziers/ice shards/stone circle.
- **Character:** `character_visuals` ground shadow + breathing, `enemy_feedback` crit 1.22 + elite aura, `enemy_base` crit branch, `effect_director` 10/14 bursts 22×0.68s skill colors + projectile/skill/levelup wiring, `player_animation` skill/victory (10 skill map, Cheer), `enemy_animator` stun/cast+telegraph, `boss_controller` phase visuals + lights + audio, `procedural_sfx` 10→28 cues, `skill/wave/experience` audio triggers, `catalog` 7 cues, `upgrade_panel` rarity borders, `touch_controls` 64/52, `camera_rig` combat shake wiring.
- All 48 commits ahead include hardening (seed, health finite, spawn bounds), lifecycle stress tests, determinism fixes.

## Content matrix (EXISTS → LOADS → GAMEPLAY INTEGRATED → VISUALLY INTEGRATED → AUDIO INTEGRATED → TESTED → DOCUMENTED)

### Weapons (9, 6 live + 3 pending)
| ID | Exists | Loads | Gameplay | Visual | Audio | Tested | Doc |
|---|---|---|---|---|---|---|---|
| gladius | tres | ✓ via ContentRegistry | WeaponManager→Instance→MeleeResolver | PlayerEquipment sword_1handed socket.r | player_attack | test_weapons | catalog |
| sentinel_spear | tres | ✓ | →Instance→Melee (stab) | Spear socket.r | player_attack | ✓ | catalog |
| stormhammer | tres | ✓ | →Instance→Melee | Hammer socket.r | player_attack | ✓ | catalog |
| sunbow | tres | ✓ | →Instance→Ranged volley Pool | Bow socket.r (ranged) + muzzle | player_shot/reload | ✓ | catalog |
| twinfangs | tres | ✓ | →Instance→Flurry | dagger dual-wield l+r | player_attack | ✓ | catalog |
| warreaxe | tres | ✓ | →Instance→Melee | axe socket.r | player_attack | ✓ | catalog |
| ember_scepter | tres | ✓ | →Instance→Volley burn | **PENDING** (Skeleton_Staff exists, not mounted) | fallback | static | catalog pending |
| moonlance | tres | ✓ | →Instance→Hybrid frost/slow | **PENDING** (reuse Spear) | fallback | static | pending |
| venom_chain | tres | ✓ | →Instance→Flurry poison | **PENDING** (reuse Dagger) | fallback | static | pending |
**Action (M1):** integrate 3 pending into PlayerEquipment or set `disabled=true` so not selectable.

### Skills (8, all enabled, 5 spec +3 extra)
| ID | Behavior | Gameplay | Visual distinct | Audio | Tested |
|---|---|---|---|---|---|
| bladestorm | whirl | SkillExecutor whirl 5 hits bleed | EffectDirector ring 2.8 + burst 1.35 gold bleed | skill_cast | ✓ |
| frost_nova_skill | frost_nova | radial slow+exposed | ring 4.2 ice burst | skill_cast | ✓ |
| phantom_rush | dash_strike | travel+strikes | ring 2.8 purple dash | skill_cast | ✓ |
| seismic_slam | slam | radial 4.5 knock14 | ring 3.6 brown | skill_cast | ✓ |
| warcry_skill | warcry | self warcry/frenzy | ring 2.8 orange | skill_cast | ✓ |
| chain_lightning | chain_lightning | shock chain 5 | generic (needs distinct) | skill_cast | static |
| mending_light | heal_surge | heal+regen/overguard | generic raise | skill_cast | static |
| shatterwave | shockwave | line frost slow | generic | skill_cast | static |
Distinctness: 5 spec have colors; 3 extra share generic raise/shoot — M2 will distinctify and add camera.

### Enemies (8)
| ID | Model | Anims idle/run/attack/hurt/death | Special | Scale/facing | Audio | Tested |
|---|---|---|---|---|---|---|
| basic/skeleton_Minion | ✓ | ✓ (95) | — | 1.72 PI | hit/death | ✓ |
| fast/Rogue | ✓ | ✓ dagger stab | — | 1.70 | ✓ | ✓ |
| heavy/Warrior | ✓ | ✓ chop | poise | 1.95 | ✓ | ✓ |
| ranged/Mage | ✓ | ✓ Spellcast_Shoot | cast (mapped to cast clip) | 1.72 | ✓ | ✓ |
| dasher/Rat | ✓ | Rat_* 6 | dash charge | 0.85 | windup/dash | ✓ |
| splitter/Spider | ✓ | Spider_* 5 | fuse→scatter via ledger | 1.00 | explosion | ✓ |
| exploder/Demon | ✓ | 14 Punch/HitReact | fuse exploder | 1.65 | explosion | ✓ |
| warlord/BlueDemon | ✓ | 14 Boss 3 phases | slam/charge/summon telegraph 0.8/0.6/1.0 | 2.45 | boss cues | ✓ |
Mage/Rat/Spider visuals flagged for scale/facing recheck in M2.

### Boss phases (warlord, 3)
- Thresholds 1.0 Awakening, 0.66 Fury (+25% dmg 10% speed), 0.33 Enrage (+50% dmg 25% speed, cleanse). Deterministic rng `run_seed*31+hash`. Visual: tint white→orange→red emissive + scale 1→1.24 + light 5→8. HUD via `boss_phase_changed`.

### Status (13, 8 required +5 extra)
Bleed/Burn/Guard/Regen/Shock/Slow/Stun/Warcry required — all present as `data/status/*.tres`. Extra: exposed, frenzy, haste, overguard, poison. Applied via `StatusManager` (stack/refresh, shield), VFX via `effect_director` ring+burst per color, audio silent (will map). Lifecycle refresh/expire/cleanse/death tested.

### Pickups (6) — all pooled 32/ max24
health_orb, stamina_brew, antidote, xp_gem, magnet_core, coin_cache — `PickupManager` scatter 0.8, magnet accelerating, bob 1.5 rot, `effect_director` ring spawn/collect, `pickup` SFX, ledger roll_drops tested.

### Arenas (3)
default_arena The Pit, ember_crucible, frost_hollow — `Arena` floor 22m, themes, `ArenaDecorator` 22 clutter max +8 pillars, `Hazards` vents, `camera_profile` 8/4/70/6. FPS hazard/spawn/boss path verified statically.

### VFX
`EffectDirector` pooled MAX_BURSTS 10 MAX_RINGS 14 MAX_MUZZLE 4, burst 22×0.68s, priority CRITICAL/BOSS/PLAYER/SKILL/ENEMY_DEATH/HIT handled, saturation preserves critical/boss, diagnostics removed (only `report_info`).

### Audio cues (28 procedural + 24 catalog)
LIVE: player_attack/hurt/death/dodge/step/switch/shot/reload/low_health, enemy_hit/death/attack/spawn/windup/dash/explosion, pickup/upgrade_select/ui_confirm/back, skill_cast/ready, level_up, wave_started/completed, boss_spawned/phase/slain, game_over, footstep/equip/item_drop, arena_menu/gameplay.
FALLBACK: procedural builds AudioStreamRandomizer if file missing (deterministic seeds). RESERVED: unused tag `exposed` etc. Tested via `validate_assets` cue coverage.

### Animation states
Player Knight 76 clips (Idle/Walk/Run/Attacks/Dodge 4/Hit/Death/Cheer/Spellcasts), all ENEMIES have idle/run/attack/hurt/death; dasher/rat 6, spider 5, demon 14 verified via `models` skins.

### UI screens
Menu, Setup, HUD (HP/Stamina/XP/Wave/Score/Combo/Currency/Weapon), SkillBar, UpgradePanel (3 cards rarity), Pause, GameOver/Summary, Armory (30 upgrades), Settings, Help, BossBar, TouchControls, Minimap, Announcements, DamageNumbers — all exist, loads, touch 64/52, safe-area.

## Marker classification (grep TODO/FIXME/PLACEHOLDER/HACK/STUB/DEBUG)
- Zero TODO/FIXME/PLACEHOLDER in scripts/scenes (only `MAX_FAILED_ATTEMPTS=6` constant, not marker).
- DEBUG: `damage_number_layer` reduced-motion jitter `randf_range(-12,12)` — KEEP (cosmetic, bounded).
- Compatibility stubs: `AttackController`/`ComboChain` still present but isolated — **M3 will remove or document** if unused.
- `PRINT` diagnostics removed; only bounded `EventBus.report_info` remains — KEEP.

## Determinism audit
- **Gameplay RNG (deterministic, salted `RngService`):** `STREAM_ARENA` decorator/hazards, `STREAM_AI` enemy approach/jitter/elite, `STREAM_DROPS` pickup scatter/magnet, `STREAM_CRITS` crit, `STREAM_WAVES` wave planner/mutators, `STREAM_AI` boss ability picks (RNG seeded `run_seed*31+hash(archetype)`), spawn jitter, daily challenge, upgrade selector (local RNG `hash_seed(run,wave)`). All reseed per run/wave.
- **Cosmetic RNG (intentionally non-deterministic, non-authoritative):** `camera_rig` shake `randf_range(-1,1)*strength` (visual only), `damage_number_layer` x-jitter, `procedural_sfx` seeded 42/99/777/1234 fixed (deterministic output), `game_root` initial seed `randi()+Time.get_ticks_msec()` for new run (acceptable, subsequent determinism via `RngService`).
- **No gameplay damage/AI/spawn uses bare `randf`/`randi` without `RngService` except `procedural_sfx` generation (cosmetic) and `run_setup_panel` `randi()` for UI shuffle (cosmetic).
- Classification: **PASS** — gameplay is deterministic, cosmetic is bounded and documented.

## Stop conditions for M0
- No unclear ownership: runtime code is truth, docs reconciled afterward — **CLEAR**.
- No duplicate planned work — **CONFIRMED**.
- Gameplay RNG is deterministic or explicitly cosmetic — **CONFIRMED**.
- Proceed to M1.
