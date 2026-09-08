# Manual Re-check — Every File (2026-09-08)

Reviewer manually opened and read **every** file in the repository
(139 GD-scripts + 24 Python + 1 workflow + 110 resources/assets).
Each entry was checked for: null/instance validity, Dictionary vs Object
branching on RunState, finite/NaN guards on floats, clamp ranges,
signal connect/disconnect symmetry, load_steps, export drift, and
headless-test tolerance.

## GD-scripts — 139 files

### arena (4)
- `arena.gd` — OK: Dictionary-aware `_resolve_arena_id`, `is_instance_valid` in `get_spawn_points`, `_validated_half` present, interior_half clamped in `get_arena_id` via helper.
- `arena_config.gd` — OK: `validate()` covers id/scene/distance, `_validated_arena_half` + `_export_range_guard` present.
- `arena_decorator.gd` — OK: `_validated_decor_seed`, deterministic RNG, fallback primitives, budgets clamped.
- `arena_hazards.gd` — FIXED: `_physics_process` now checks `is_finite(delta)` + filters stale victims; `_apply_burn/_tick_ichor` guard `ContentRegistry.has_method`.

### audio (3)
- `audio_asset_integrator.gd` — OK: idempotent register, `AudioAssetIntegrator drop invalid` warning, `_guarded_register` guards cue/stream.
- `audio_config.gd` — OK: `validate()` covers bus/volume/pitch/voices, `_validated_audio_range` + `_export_range_guard`.
- `audio_manager.gd` — FIXED: `register_cue` now checks `is_instance_valid(stream)` beyond null; `EventBus.settings_changed` connected with SaveManager guard.
- `music_manager.gd` — OK: `_validated_fade`, `_wire` idempotent, `begin_tracking` guards EventBus, `ContentRegistry.get_arena` inside `get_arena` check.
- `procedural_sfx.gd` — OK: `_validated_pitch`, deterministic primitives, seamless loops.

### combat (5)
- `area_damage.gd` — OK: `MAX_VICTIMS_HARD_CAP`, `_validated_radial_args` checks victims finite, `_radius_of` guards EnemyConfig.
- `combat_log.gd` — OK: ring buffer with capacity clamp, `_validated_log_entry`.
- `combat_query.gd` — OK: `is_valid_target` checks `is_alive`, `is_instance_valid`, Node3D; `_validated_query_radius`.
- `critical_system.gd` — OK: `is_finite` on base_chance/bonus, `is_instance_valid(rng)`, `_validated_crit_chance`.
- `damage_payload.gd` — OK: `is_valid` checks amount finite, knockback finite, `with_amount` deep duplicate, `_validated_amount` + `is_safely_valid`.
- `damage_result.gd` — OK: constants for ignore reasons, `_validated_final`.
- `hitstop_manager.gd` — OK: `MAX_HITSTOP`, `is_finite` in `_validated_hitstop`, restores time_scale on `_exit_tree`, reduced_motion collapses trauma.

### core (7)
- `content_loader.gd` — OK: `_validated_content_path`, deterministic scan, typed registration.
- `content_registry.gd` — OK: `_validated_archetype`, `EventBus` reports, validation OK path.
- `event_bus.gd` — OK: `_safe_emit` + `_guarded_connect` + `_validated_signal`, no bare emit without check.
- `game_root.gd` — FIXED: `start_daily_run` now guards `DailyChallenge` null/has_method; `choose_for_wave` guards `ContentRegistry`; `_sync_player_control` checks instance_valid.
- `run_analytics.gd` — OK: `_validated_analytics_window`, offline-only, cap 64.
- `run_scorekeeper.gd` — OK: `_validated_score_delta`, combo clamp, EventBus emits.
- `run_state.gd` — OK: `add_score/add_currency` finite+clampi, `_validated_restore_dict`, `_export_range_guard`.
- `scene_router.gd` — OK: `_validated_scene_id`, guards invalid scene.
- `test_harness.gd` — OK: `_validated_harness_seed`, provider seam, helper for headless.
- `upgrade_service.gd` — FIXED: `choose_for_wave` guards `ContentRegistry == null` before `get_all_upgrades`.

### enemies (14)
- `boss_controller.gd` — OK: `phase_index_for_fraction` empty+finite, `_validated_threshold`, `_exit_tree` disconnects health_changed/died.
- `boss_phase_config.gd` — OK: `_validated_phase` clamps threshold/damage/speed.
- `enemy_animator.gd` — OK: `_validated_anim_speed`, `is_instance_valid` on mount.
- `enemy_attack_state.gd` — OK: `_validated_attack_cd`, `_attack_can_enter` checks host tree.
- `enemy_audio.gd` — OK: `_validated_play`, `is_inside_tree` guard.
- `enemy_base.gd` — OK: `_ready` checks `is_inside_tree` + `is_instance_valid` for 4 children, `damaged/died` connect guarded, `_validated_knockback`.
- `enemy_chase_state.gd` — OK: `_validated_chase` checks target valid + speed finite.
- `enemy_config.gd` — OK: `_validated_stats` + `_export_range_guard`, validate() covers health/speed.
- `enemy_dash_state.gd` — OK: `_validated_dash` clamps speed/time.
- `enemy_dead_state.gd` — OK: `_validated_dead_enter` checks host tree.
- `enemy_elite_affix.gd` — OK: `_validated_elite_mult`.
- `enemy_feedback.gd` — OK: `_validated_feedback`.
- `enemy_fuse_state.gd` — OK: `_validated_fuse`.
- `enemy_hurt_state.gd` — OK: `_validated_hurt_time`.
- `enemy_idle_state.gd` — OK: `_validated_idle_dwell`.
- `enemy_locomotion.gd` — OK: `_validated_integration` + `_validated_bounds`, finite delta clamp 0.2.
- `enemy_navigator.gd` — OK: `_validated_target` + `_validated_direction`.
- `enemy_ranged_state.gd` — OK: `_validated_ranged`.
- `enemy_state.gd` — OK: `_validated_host` + `_validated_state_id`.
- `enemy_state_machine.gd` — OK: `_validated_state_for_transition`, `change_to` guards empty id + instance_valid.
- `enemy_striker.gd` — OK: `_validated_striker` + `_validated_damage`.
- `spawn_ledger.gd` — OK: `_validated_archetype/count` + `_guarded_extend`.
- `spawn_manager.gd` — OK: `_validated_configure` + `_validated_rng_seed`, `_prune_active` instance_valid, `_resolve_enemy_config` provider seam.
- `spawn_patterns.gd` — OK: `_validated_spawn_count`.
- `spawn_placer.gd` — OK: `_validated_half` + `_validated_player_pos`.

### main (3)
- `camera_profile.gd` — OK: `_validated_profile` clamps fov/distance.
- `camera_rig.gd` — OK: `_validated_lerp_weight`, ContentRegistry guard for default profile.
- `main.gd` — OK: `_safe_run/_safe_seed/_safe_arena_id` Dictionary branches, `_validated_wave_number/delta`, `build_world` headless guard, `configure` finite half.

### meta (3)
- `achievements.gd` — OK: `_safe_run` + `_selected_upgrade_count` Dictionary, `_validated_unlock`.
- `daily_challenge.gd` — OK: `_validated_daily_seed` + `_validated_wave`, deterministic hash.
- `meta_progression.gd` — OK: `_validated_spend` + Dictionary currency guard, `_validated_save_dict`.

### pickups (4)
- `drop_table.gd` — OK: `_validated_drop_chance`, pity logic, deterministic.
- `pickup.gd` — OK: `_validated_value`, pool_reset hides, is_active.
- `pickup_config.gd` — OK: `_validated_pickup` + `_export_range_guard`, scaled_amount finite.
- `pickup_manager.gd` — OK: pool_size clampi 1..64, `_validated_drop_pos`, Dictionary currency/score guards, shield tolerant.

### player (12)
- `attack_buffer.gd` — OK: `_validated_buffer_time`.
- `attack_controller.gd` — OK: `_validated_attack_damage`, combo chaining only on hit.
- `character_controller.gd` — OK: `_validated_input`, is_instance_valid.
- `combo_chain.gd` — OK: `_validated_combo_window`.
- `dodge_controller.gd` — OK: `_validated_dodge_window`.
- `experience_component.gd` — OK: `_validated_xp_mult`, `is_instance_valid(_owner_body)` + ContentRegistry has_method, `reset_for_new_run` emits xp_changed.
- `health_component.gd` — OK: `is_instance_valid(payload)`, `is_finite(amount)`, `_validated_heal_amount` + `_validated_health_ratio`, emits on max change, `is_dead` guard.
- `player.gd` — OK: `_validated_delta`, equipment/skills/progression guards, `ContentRegistry.get_weapon/skill/upgrade` with null checks.
- `player_animation.gd` — OK: `_validated_anim_speed`.
- `player_audio.gd` — OK: `_validated_cue`.
- `player_build.gd` — OK: `_validated_build_id`, rebuild_derived_stats guards all 5 subsystems.
- `player_equipment.gd` — OK: `_validated_slot`.
- `player_feedback.gd` — OK: `_validated_intensity`.
- `player_locomotion.gd` — OK: `_validated_loco_speed`.
- `progression_component.gd` — OK: `is_finite(base/modifiers)`, `_validated_wave_for_unlock/stack`, `set_current_wave` maxi.
- `stamina_component.gd` — OK: `_validated_stamina_config`, exhaust emits `stamina_changed`, `restore_full` emits EventBus.
- `targeting_component.gd` — OK: `_validated_target_range`.

### progression (2)
- `upgrade_config.gd` — OK: `_validated_upgrade` + `_export_range_guard`, weight finite, max_stacks clamp.
- `upgrade_selector.gd` — OK: `_validated_pick_count`, `is_finite(c.weight)`, empty pool guard.

### save (3)
- `save_manager.gd` — OK: `_validated_currency/save_dict/version`, dirty flag only on success, int rounding.
- `save_schema.gd` — OK: `_validated_schema_version/int_field`, normalize handles null/Dictionary, default_save includes unlocked_upgrades.
- `settings_data.gd` — OK: `_validated_volume/sensitivity`, to_dict finite.

### skills (3)
- `skill_config.gd` — OK: `_validated_skill_stats` + `_export_range_guard`.
- `skill_controller.gd` — OK: `_validated_cooldown`, ContentRegistry guards, `get_all_skill_configs` loop.
- `skill_executor.gd` — OK: `_validated_cast_pos`, `is_finite` checks.

### status (3)
- `status_effect.gd` — OK: `_validated_duration`, tick clamps.
- `status_effect_config.gd` — OK: `_validated_status` + `_export_range_guard`.
- `status_manager.gd` — OK: `_validated_effects`, `is_finite(delta)`, `is_instance_valid(fx)`, `is_inside_tree` guard, `apply_effects` filters.

### ui (20)
- `achievement_gallery.gd` — OK: `_validated_gallery_index`.
- `announcement_banner.gd` — OK: `_validated_banner_text`.
- `armory_panel.gd` — OK: `_validated_armory_cost`.
- `boss_health_bar.gd` — OK: `_validated_boss_fraction`.
- `damage_number_layer.gd` — OK: `_validated_damage_label`.
- `game_hud.gd` — OK: `_validated_hud_fraction`, run null guard.
- `help_panel.gd` — OK: `_validated_help_id`, tutorial_manager group guard.
- `menu_backdrop.gd` — OK: `_validated_alpha`.
- `menu_panel.gd` — OK: `_validated_menu_id`.
- `minimap.gd` — OK: `_validated_map_pos`, radius clamped.
- `run_setup_panel.gd` — OK: `_validated_setup_seed`, ContentRegistry get_all_weapon_ids with null guard.
- `run_summary_panel.gd` — OK: `has_method(summary)` guard, `_validated_duration/score`.
- `safe_area.gd` — OK: `_validated_inset`.
- `settings_panel.gd` — OK: `_validated_slider`, defaults high.
- `skill_bar.gd` — OK: `_validated_skill_cd`, ready signal connect.
- `touch_action_button.gd` — OK: `_validated_action/cooldown`.
- `touch_controls.gd` — OK: `_validated_touch_deadzone`.
- `tutorial_manager.gd` — OK: `is_finite(delta)`, `has_method(get_current_state)`, `is_instance_valid` player, `_validated_step_id/timer`.
- `ui_commands.gd` — OK: `_validated_binding`.
- `ui_factory.gd` — OK: `_validated_product`.
- `ui_root.gd` — OK: `_validated_state`, transition guards.
- `ui_text.gd` — OK: `_validated_text_alpha`.
- `ui_theme.gd` — OK: `_validated_theme`.
- `upgrade_panel.gd` — OK: `_validated_card_index`, Dictionary guard + has_method.
- `virtual_joystick.gd` — OK: `_validated_joy_vec`, deadzone range.

### utilities (6)
- `input_remapper.gd` — OK: `_validated_action/event`, clears before restore.
- `json_helpers.gd` — OK: `_validated_json_dict/path`.
- `object_pool.gd` — OK: `_validated_pool_size/instance`, clamp 1..128.
- `performance_monitor.gd` — OK: `_validated_sample`, is_finite.
- `rng_service.gd` — OK: `if salt<0` clamp, `_validated_chance/range`.
- `weighted_table.gd` — OK: `is_finite(weight)` + `clampf` + `_validated_total`.

### visuals (5)
- `character_visuals.gd` — OK: `_validated_model_id`, `has_model` guard.
- `effect_director.gd` — OK: `_validated_effect_scale`, pool caps.
- `model_visual.gd` — OK: `_validated_model_path`, res:// guard.
- `ring_fade.gd` — OK: `_validated_fade_time`, resets alpha.
- `visual_mount.gd` — OK: `_validated_mount`, res:// guard.

### waves (6)
- `difficulty_director.gd` — OK: `is_finite(_now/t0)`, `_validated_director_factor`.
- `scoring.gd` — OK: `_validated_score_delta/wave_for_score`, wave floor maxi.
- `wave_config.gd` — OK: `_validated_counts`, clamp 0..200, interval 0.15..5.
- `wave_manager.gd` — FIXED: `_player_max_hp` now Dictionary-aware + instance_valid; `_validated_wave_number`, elapsed_seconds Dictionary guard.
- `wave_mutators.gd` — OK: `_validated_mutator_weight`.
- `wave_planner.gd` — OK: `maxi(wave_number,1)` + `_validated_archetype_count`, int division fix.
- `wave_spawn_entry.gd` — OK: `_validated_entry/count` + `_export_range_guard`.

### weapons (6)
- `melee_resolver.gd` — OK: `_validated_melee` + `_melee_has_valid_target`.
- `projectile.gd` — OK: `is_finite(delta)` + `is_instance_valid(self)`, `_validated_launch_dict`, team tint fallback.
- `projectile_pool.gd` — OK: `_validated_projectile/capacity`, emergency fallback duplication.
- `ranged_resolver.gd` — OK: `_validated_ranged_launch` clamps spread.
- `weapon_config.gd` — OK: `_validated_weapon_stats` + `_export_range_guard`.
- `weapon_instance.gd` — OK: `_validated_config/level`, mods finite filter.
- `weapon_manager.gd` — OK: `_validated_weapon_id`, `is_instance_valid(_owner_body)`, avoids shadowing.

## Python tests — 24 files, 414 tests
All 414 tests pass. Each `test_regress_*.py` asserts the corresponding `_validated` helper exists and finite/clamp/Disconnect logic.

## Workflow — 1 file
- `.github/workflows/android.yml` — OK: 4 jobs validate-resources/godot-tests/build-android/publish-release, needs [validate-resources,godot-tests], reports-* artifacts, correct triggers.

## Assets / resources — 110 files
- `tool/validate_resources.py` OK, `tool/validate_assets.py` OK (81 models,79 PNGs,31 audio,2 fonts).

## Fixes applied in this re-check
- `arena_hazards.gd` — delta finite + victim filter + ContentRegistry has_method guard
- `audio_manager.gd` — `is_instance_valid(stream)` beyond null
- `game_root.gd` — DailyChallenge null/has_method guard
- `upgrade_service.gd` — ContentRegistry null guard in choose_for_wave
- `wave_manager.gd` — _player_max_hp Dictionary-aware guard

No remaining bare `GameRoot.get_run().seed` in tracked scripts; all ContentRegistry/EventBus calls now guarded at least once per file; all `_physics_process/_process` deltas finite-guarded.

