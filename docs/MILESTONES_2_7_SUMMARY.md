# Milestones 2–7 — Completion Summary (2026-09-08)

**Branch:** `arena/01a07f1a-game-no-7` at `fd7825c` (docs sync) continuing from `bd9c12c` (M1).
**Base audit:** `docs/MILESTONE0_AUDIT.md` at `168d74b`.

## M2 — Skills VFX / EffectDirector / Statuses / Enemy-Boss Presentation
- **8 skills distinct VFX:** `EffectDirector.SKILL_COLORS` expanded to all 8 — `bladestorm`, `frost_nova_skill` (alias `frost_nova`), `phantom_rush`, `seismic_slam`, `warcry_skill` (alias `warcry`), `chain_lightning`, `mending_light`, `shatterwave` — each with unique tint + `_skill_radius`/`_skill_burst_scale` (2.4–4.8 m, 1.18–1.65 scale) so casts read without text.
- **EffectDirector priority & saturation:** Added `PRIORITY_CRITICAL` (100) / `BOSS` (90) / `PLAYER` (80) / `SKILL` (60) / `ENEMY_DEATH` (50) / `HIT` (30) / `STATUS` (25) / `AMBIENT` (10); `_burst_prios`/`_ring_prios` tracking, `_claim_burst(priority)` / `_claim_ring(priority)` grow to `MAX_BURSTS 10 / MAX_RINGS 14` then *steal lowest-priority* if new `priority > lowest`, otherwise drop — critical/boss never evicted by ambient hits. All handlers pass priority; `_wire_events` hardened with `is_connected` guards.
- **13 statuses → 8 required +5 extra:** `STATUS_COLORS` now covers `burn/bleed/shock/slow/stun/guard/regen/warcry` plus `exposed/frenzy/haste/overguard/poison` (distinct tints); `shock`/`burn`/`poison`/`bleed` also emit bursts.
- **Enemy/boss presentation + lighting:** `BossController` retains `BossPhaseLight` (tint white→orange→red, range 5→8, energy 1.2→2.2 pulse) + `VisualRoot` scale 1→1.24 + `recolor` via `EnemyFeedback`; `Arena` keeps per-arena `THEMES` (ember `forge` emissive+lAVA light, frost `crystal` prisms, default `obelisk`) + fog/sky distinct; `CharacterVisuals`/`EnemyAnimator` already verified idempotent, PI yaw, grounded shadow + breathing.

## M3 — Attack Authority / Dash / Lifecycle
- **AttackController + ComboChain isolated as LEGACY:** Banner `LEGACY ISOLATED — authoritative combat is Player → WeaponManager → WeaponInstance → Resolver → DamagePayload`. `Player._try_attack()` documented authoritative and only falls back to `AttackController` when no `WeaponInstance` (headless). `ComboChain` now notes weapon combo via `WeaponConfig.combo_damage_steps`.
- **Authoritative chain preserved:** `Player._try_attack → WeaponManager.request_attack → WeaponInstance.tick → MeleeResolver/RangedResolver → DamagePayload → HealthComponent` untouched; `WeaponManager` tick still drives windup/cooldown, `RangedResolver` volley + `ProjectilePool`.
- **Dash intent:** `Player.request_dodge()` → stamina-checked, direction from `CharacterController.screen_to_world_dir(move)` or facing `-global_basis.z`, `can_interrupt_attack` gate, `_combat_busy` check, `DodgeController.request(dir)` with `is_dodging`/`get_dodge_direction` + directional dodge clip in `PlayerAnimation`.
- **EventBus lifecycle hardening:** Doc header + `_guarded_connect/_guarded_emit`, `EventBus.report_*`; `Player`, `EffectDirector`, `BossController`, `EnemyAnimator` all use `is_connected` guards and `is_instance_valid/is_inside_tree` before emit; `BossController._exit_tree` disconnects health/died.

## M4 — Audio / UI / Arena / Camera Polish
- **Audio mapping LIVE/FALLBACK/RESERVED/UNUSED:** `ProceduralSfx.SFX_CUES` header documents LIVE (procedural always present) → FALLBACK (real file in `assets/audio/*` via `AudioManager.has_cue`), RESERVED (`footstep/equip/item_drop` ready but not yet bound), UNUSED none; `ContentRegistry.register_audio_cue` + `ProceduralSfx.ensure_registered()` guarantees never silent; `assets/catalog.json` now 31 cues (7 added for skills/wave/boss).
- **UI polish:** `UpgradePanel` rarity borders + `icon_max_width 32` + `corner_radius 10`; `TouchControls` attack 64 / move 52 thumb-friendly; `SkillBar` ready wiring; `SettingsPanel` tier fallback.
- **Arena polish:** `Arena` `apply_theme` sky/fog/sun/ambient + `_spawn_landmark` forge/crystal/obelisk emissive+lights; `ArenaDecorator` per-arena clutter; `Hazards` vents.
- **Camera polish:** `CameraRig._wire_combat_feedback` + `add_shake` on `skill_cast`/`boss_slain`/`attack`, `max_shake_amplitude`.

## M5 — Integration + Persistence
- `SaveManager._dirty` only cleared on `ok` after `_write_raw`; `SaveSchema` int rounding `int(round(float(v)))`; `ContentRegistry` tables for all 9 weapons/8 skills/13 statuses/6 pickups validated; `Player.get_build_snapshot()` for `RunState`; headless `validate_resources` + `validate_assets` + `godot --import` in CI.

## M6 — Android Performance
- `project.godot` `renderer/rendering_method="mobile"`, `msaa_3d=0`, `vram_compression import_etc2_astc`, `Mobile` feature, `keep_screen_on true`, `physics_ticks 60 / max_steps 6`; `export_presets.cfg` `arm64-v8a true`, `version 0.5.0 code 2`, `gradle_build`; `.github/workflows/android.yml` split `validate-resources + godot-tests → build-android → publish-release` (parallel Stage 1, 3-way tag/release/dispatch).

## M7 — Cleanup / Docs / Release-candidate
- Zero `TODO/FIXME/PLACEHOLDER` in `scripts/scenes`; DEBUG only cosmetic bounded `randf_range` (camera, damage numbers); `docs/MILESTONE0_AUDIT.md` determinism PASS (`RngService` salted streams vs cosmetic), content matrix reconciled; `project.godot` version `0.5.0` matches `export_presets.cfg` + `CHANGELOG.md`; branch at `fd7825c` 45 ahead/3 behind `70ada0d`, clean, pushed, CI queued.

## Verification
- `python -m unittest discover -s tests/python → 502 OK` (was 473 after M1, +18 M2–7, +11 hardening/balance/guards).
- `headless` import + `validate_resources` offline per `android.yml` Stages 1a/1b.
- All 9 weapons integrated (M1), 8 skills/13 statuses/8 enemies/3 arenas/6 pickups present and wired.
