extends RefCounted

## Headless spatial-attenuation + mix-snapshot + enemy-clip catalog. No tree,
## no autoloads — deterministic math pins for the v3 world-audio / animator path.

static func suite() -> Array:
	var results: Array = []
	_attenuation(results)
	_mix(results)
	_clips(results)
	_voice_bank_tokens(results)
	return results


static func _attenuation(results: Array) -> void:
	results.append({
		"name": "gain at listener is unity",
		"passed": is_equal_approx(SpatialAttenuation.gain(0.0), 1.0),
		"why": str(SpatialAttenuation.gain(0.0)),
	})
	var g_near := SpatialAttenuation.gain(4.0)
	var g_far := SpatialAttenuation.gain(24.0)
	results.append({
		"name": "inverse rolloff is monotone-quieter with distance",
		"passed": g_near > g_far and g_far > 0.0 and g_near < 1.0,
		"why": "near=%f far=%f" % [g_near, g_far],
	})
	results.append({
		"name": "gain is silent at max_distance",
		"passed": SpatialAttenuation.gain(SpatialAttenuation.DEFAULT_MAX_DISTANCE) == 0.0,
		"why": "",
	})
	results.append({
		"name": "cull past CULL_DISTANCE",
		"passed": SpatialAttenuation.should_cull(SpatialAttenuation.CULL_DISTANCE)
			and not SpatialAttenuation.should_cull(8.0),
		"why": "",
	})
	var inv := SpatialAttenuation.gain(10.0, 8.0, 42.0, SpatialAttenuation.MODEL_INVERSE)
	var sq := SpatialAttenuation.gain(10.0, 8.0, 42.0, SpatialAttenuation.MODEL_INVERSE_SQUARE)
	var lin := SpatialAttenuation.gain(10.0, 8.0, 42.0, SpatialAttenuation.MODEL_LINEAR)
	results.append({
		"name": "inverse-square is quieter than inverse at the same distance",
		"passed": sq < inv and lin > 0.0,
		"why": "inv=%f sq=%f lin=%f" % [inv, sq, lin],
	})
	var db := SpatialAttenuation.db_from_gain(0.5)
	results.append({
		"name": "db_from_gain(0.5) is about -6 dB",
		"passed": db < -5.5 and db > -6.5,
		"why": str(db),
	})
	results.append({
		"name": "db_from_gain(0) is silence",
		"passed": SpatialAttenuation.db_from_gain(0.0) == SpatialAttenuation.SILENCE_DB,
		"why": "",
	})
	var clear := SpatialAttenuation.occluded_db(-8.0, 0.0)
	var blocked := SpatialAttenuation.occluded_db(-8.0, 1.0)
	results.append({
		"name": "occlusion cuts up to OCCLUSION_MAX_DB and never hard-mutes",
		"passed": is_equal_approx(clear, -8.0)
			and blocked < clear
			and blocked > SpatialAttenuation.SILENCE_DB
			and is_equal_approx(clear - blocked, SpatialAttenuation.OCCLUSION_MAX_DB),
		"why": "clear=%f blocked=%f" % [clear, blocked],
	})
	var a := Vector3(0, 0, 0)
	var b := Vector3(3, 9, 4)
	results.append({
		"name": "distance_flat ignores Y so flying tells share the XZ budget",
		"passed": is_equal_approx(SpatialAttenuation.distance_flat(a, b), 5.0),
		"why": str(SpatialAttenuation.distance_flat(a, b)),
	})
	results.append({
		"name": "NaN distance is not hearable",
		"passed": SpatialAttenuation.should_cull(NAN) or SpatialAttenuation.distance_flat(
			Vector3(NAN, 0, 0), Vector3.ZERO
		) == INF,
		"why": "",
	})
	results.append({
		"name": "clamp_unit_size / max_distance reject non-finite",
		"passed": SpatialAttenuation.clamp_unit_size(-1.0) == SpatialAttenuation.DEFAULT_UNIT_SIZE
			and SpatialAttenuation.clamp_max_distance(INF) == SpatialAttenuation.DEFAULT_MAX_DISTANCE,
		"why": "",
	})
	results.append({
		"name": "model_from_name round-trips the four models",
		"passed": SpatialAttenuation.model_from_name(&"inverse_square") == SpatialAttenuation.MODEL_INVERSE_SQUARE
			and SpatialAttenuation.model_name(SpatialAttenuation.MODEL_LOG) == &"log"
			and SpatialAttenuation.is_valid_model(SpatialAttenuation.MODEL_LINEAR)
			and not SpatialAttenuation.is_valid_model(99),
		"why": "",
	})
	var hear := SpatialAttenuation.hearable_gain(Vector3.ZERO, Vector3(6, 0, 0), 0.0)
	var culled := SpatialAttenuation.hearable_gain(Vector3.ZERO, Vector3(80, 0, 0), 0.0)
	results.append({
		"name": "hearable_gain culls past max and stays (0, 1] inside",
		"passed": hear > 0.0 and hear <= 1.0 and culled == 0.0
			and SpatialAttenuation.is_hearable(Vector3.ZERO, Vector3(6, 0, 0))
			and not SpatialAttenuation.is_hearable(Vector3.ZERO, Vector3(80, 0, 0)),
		"why": "hear=%f culled=%f" % [hear, culled],
	})
	var log_near := SpatialAttenuation.gain(2.0, 8.0, 42.0, SpatialAttenuation.MODEL_LOG)
	var log_far := SpatialAttenuation.gain(30.0, 8.0, 42.0, SpatialAttenuation.MODEL_LOG)
	results.append({
		"name": "log model is monotone-quieter",
		"passed": log_near > log_far and log_far >= 0.0,
		"why": "near=%f far=%f" % [log_near, log_far],
	})
	results.append({
		"name": "unknown model falls back to inverse",
		"passed": is_equal_approx(
			SpatialAttenuation.gain(10.0, 8.0, 42.0, 99),
			SpatialAttenuation.gain(10.0, 8.0, 42.0, SpatialAttenuation.MODEL_INVERSE)
		),
		"why": "",
	})
	results.append({
		"name": "gain_from_db inverts db_from_gain within a cent",
		"passed": absf(SpatialAttenuation.gain_from_db(SpatialAttenuation.db_from_gain(0.25)) - 0.25) < 0.01,
		"why": str(SpatialAttenuation.gain_from_db(SpatialAttenuation.db_from_gain(0.25))),
	})


static func _mix(results: Array) -> void:
	var paused := MixSnapshot.offsets_for(MixSnapshot.ID_PAUSED)
	var combat := MixSnapshot.offsets_for(MixSnapshot.ID_COMBAT)
	results.append({
		"name": "pause ducks SFX and leaves UI at unity",
		"passed": float(paused[MixSnapshot.KEY_SFX]) < 0.0
			and is_equal_approx(float(paused[MixSnapshot.KEY_UI]), 0.0)
			and is_equal_approx(float(paused[MixSnapshot.KEY_MUSIC]), 0.0),
		"why": str(paused),
	})
	results.append({
		"name": "combat snapshot is a zero offset (settings own the mix)",
		"passed": float(combat[MixSnapshot.KEY_SFX]) == 0.0
			and float(combat[MixSnapshot.KEY_UI]) == 0.0
			and float(combat[MixSnapshot.KEY_MUSIC]) == 0.0,
		"why": str(combat),
	})
	results.append({
		"name": "every snapshot keeps music offset at 0 (MusicManager owns beds)",
		"passed": MixSnapshot.music_offset(MixSnapshot.ID_MENU) == 0.0
			and MixSnapshot.music_offset(MixSnapshot.ID_PAUSED) == 0.0
			and MixSnapshot.music_offset(MixSnapshot.ID_BOSS) == 0.0
			and MixSnapshot.music_offset(MixSnapshot.ID_SILENT) == 0.0
			and MixSnapshot.music_offset(MixSnapshot.ID_UPGRADE) == 0.0
			and MixSnapshot.music_offset(MixSnapshot.ID_GAME_OVER) == 0.0,
		"why": "",
	})
	results.append({
		"name": "pause overlay wins over playing / boss",
		"passed": MixSnapshot.id_for_game_state(&"playing", true) == MixSnapshot.ID_PAUSED
			and MixSnapshot.id_for_run(&"playing", true, true) == MixSnapshot.ID_PAUSED
			and MixSnapshot.id_for_run(&"playing", false, true) == MixSnapshot.ID_BOSS
			and MixSnapshot.id_for_game_state(&"main_menu", false) == MixSnapshot.ID_MENU
			and MixSnapshot.id_for_game_state(&"upgrade_selection", false) == MixSnapshot.ID_UPGRADE
			and MixSnapshot.id_for_game_state(&"game_over", false) == MixSnapshot.ID_GAME_OVER,
		"why": "",
	})
	results.append({
		"name": "unknown state falls back to combat so a missed wire never silences",
		"passed": MixSnapshot.id_for_game_state(&"not_a_state", false) == MixSnapshot.ID_COMBAT,
		"why": "",
	})
	var composed := MixSnapshot.compose_bus_db(-6.0, -14.0, 0.0)
	results.append({
		"name": "compose_bus_db adds the snapshot offset on top of settings",
		"passed": is_equal_approx(composed, -20.0),
		"why": str(composed),
	})
	var ducked := MixSnapshot.compose_bus_db(-8.0, 0.0, 4.0)
	results.append({
		"name": "compose_bus_db applies extra duck only to the caller that asked (music)",
		"passed": is_equal_approx(ducked, -12.0),
		"why": str(ducked),
	})
	results.append({
		"name": "shaped_t is 0 at 0, 1 at 1, and 0.5 at 0.5",
		"passed": MixSnapshot.shaped_t(0.0) == 0.0
			and MixSnapshot.shaped_t(1.0) == 1.0
			and is_equal_approx(MixSnapshot.shaped_t(0.5), 0.5),
		"why": str(MixSnapshot.shaped_t(0.5)),
	})
	results.append({
		"name": "lerp_db interpolates and snapshot_fade_seconds is a short click-safe fade",
		"passed": is_equal_approx(MixSnapshot.lerp_db(-14.0, 0.0, 0.5), -7.0)
			and MixSnapshot.snapshot_fade_seconds() > 0.05
			and MixSnapshot.snapshot_fade_seconds() < 0.3,
		"why": "",
	})
	results.append({
		"name": "silent snapshot ducks SFX to the floor and leaves UI audible",
		"passed": MixSnapshot.sfx_offset(MixSnapshot.ID_SILENT) == MixSnapshot.SILENCE_DB
			and MixSnapshot.ui_offset(MixSnapshot.ID_SILENT) > MixSnapshot.SILENCE_DB,
		"why": str(MixSnapshot.offsets_for(MixSnapshot.ID_SILENT)),
	})
	results.append({
		"name": "is_known accepts the seven ids and rejects junk",
		"passed": MixSnapshot.is_known(MixSnapshot.ID_COMBAT)
			and MixSnapshot.is_known(MixSnapshot.ID_PAUSED)
			and not MixSnapshot.is_known(&"jazz"),
		"why": "",
	})
	results.append({
		"name": "ui_follows_sfx only in combat (pause must isolate the UI bus)",
		"passed": MixSnapshot.ui_follows_sfx(MixSnapshot.ID_COMBAT)
			and not MixSnapshot.ui_follows_sfx(MixSnapshot.ID_PAUSED),
		"why": "",
	})
	results.append({
		"name": "clamp_offset rejects NaN / overshoot",
		"passed": MixSnapshot.clamp_offset(NAN) == 0.0
			and MixSnapshot.clamp_offset(99.0) == MixSnapshot.OFFSET_MAX
			and MixSnapshot.clamp_offset(-120.0) == MixSnapshot.OFFSET_MIN,
		"why": "",
	})
	var menu := MixSnapshot.sfx_offset(MixSnapshot.ID_MENU)
	var upgrade := MixSnapshot.sfx_offset(MixSnapshot.ID_UPGRADE)
	results.append({
		"name": "menu ducks SFX harder than upgrade (combat bleed vs card pick)",
		"passed": menu < upgrade and upgrade < 0.0,
		"why": "menu=%f upgrade=%f" % [menu, upgrade],
	})


static func _clips(results: Array) -> void:
	results.append({
		"name": "locomotion vs one-shot partition is complete and disjoint",
		"passed": EnemyClipCatalog.is_locomotion(EnemyClipCatalog.KEY_IDLE)
			and EnemyClipCatalog.is_locomotion(EnemyClipCatalog.KEY_RUN)
			and EnemyClipCatalog.is_one_shot(EnemyClipCatalog.KEY_ATTACK)
			and EnemyClipCatalog.is_one_shot(EnemyClipCatalog.KEY_DEATH)
			and EnemyClipCatalog.is_one_shot(EnemyClipCatalog.KEY_TELEGRAPH)
			and EnemyClipCatalog.is_one_shot(EnemyClipCatalog.KEY_DASH)
			and not EnemyClipCatalog.is_one_shot(EnemyClipCatalog.KEY_IDLE)
			and EnemyClipCatalog.is_known_key(EnemyClipCatalog.KEY_SPAWN),
		"why": "",
	})
	results.append({
		"name": "locomotion_for_state: chase/run, dash/dash, idle+fuse/idle",
		"passed": EnemyClipCatalog.locomotion_for_state(&"chase") == EnemyClipCatalog.KEY_RUN
			and EnemyClipCatalog.locomotion_for_state(&"dash") == EnemyClipCatalog.KEY_DASH
			and EnemyClipCatalog.locomotion_for_state(&"fuse") == EnemyClipCatalog.KEY_IDLE
			and EnemyClipCatalog.locomotion_for_state(&"idle") == EnemyClipCatalog.KEY_IDLE,
		"why": "",
	})
	results.append({
		"name": "holds_pose_in_state for ranged and stunned",
		"passed": EnemyClipCatalog.holds_pose_in_state(&"ranged")
			and EnemyClipCatalog.holds_pose_in_state(&"stunned")
			and not EnemyClipCatalog.holds_pose_in_state(&"chase"),
		"why": "",
	})
	results.append({
		"name": "finite_length rejects non-positive / NaN",
		"passed": EnemyClipCatalog.finite_length(0.0) == EnemyClipCatalog.MIN_CLIP_LENGTH
			and EnemyClipCatalog.finite_length(-1.0) == EnemyClipCatalog.MIN_CLIP_LENGTH
			and EnemyClipCatalog.finite_length(NAN) == EnemyClipCatalog.MIN_CLIP_LENGTH
			and is_equal_approx(EnemyClipCatalog.finite_length(1.2), 1.2),
		"why": "",
	})
	var slow := EnemyClipCatalog.windup_speed(1.0, 0.8)
	var fast := EnemyClipCatalog.windup_speed(1.0, 0.05)
	results.append({
		"name": "windup_speed scales the clip into the tell and clamps",
		"passed": slow < 1.2 and fast >= 0.5 and fast <= 3.0
			and EnemyClipCatalog.windup_speed(1.0, 0.0) == 1.0,
		"why": "slow=%f fast=%f" % [slow, fast],
	})
	results.append({
		"name": "telegraph_speed maps a 2s clip onto a 1s tell inside [0.5, 2.5]",
		"passed": EnemyClipCatalog.telegraph_speed(2.0, 1.0) <= 2.5
			and EnemyClipCatalog.telegraph_speed(2.0, 1.0) >= 0.5,
		"why": str(EnemyClipCatalog.telegraph_speed(2.0, 1.0)),
	})
	results.append({
		"name": "run_pace clamps around the 3.5 m/s reference",
		"passed": is_equal_approx(EnemyClipCatalog.run_pace(3.5), 1.0)
			and EnemyClipCatalog.run_pace(0.0) == 0.7
			and EnemyClipCatalog.run_pace(20.0) == 1.8,
		"why": "",
	})
	results.append({
		"name": "blend_for attack lengthens on slow windups",
		"passed": EnemyClipCatalog.blend_for(EnemyClipCatalog.KEY_HURT) == EnemyClipCatalog.DEFAULT_BLEND
			and EnemyClipCatalog.blend_for(EnemyClipCatalog.KEY_ATTACK, 0.1) == EnemyClipCatalog.DEFAULT_BLEND
			and EnemyClipCatalog.blend_for(EnemyClipCatalog.KEY_ATTACK, 0.4) == EnemyClipCatalog.ATTACK_BLEND_SLOW,
		"why": "",
	})
	var have := func(key: StringName) -> bool:
		return key in [EnemyClipCatalog.KEY_HURT, EnemyClipCatalog.KEY_ATTACK, EnemyClipCatalog.KEY_RUN]
	results.append({
		"name": "resolve_key: stun falls back to hurt, telegraph to attack, dash to run",
		"passed": EnemyClipCatalog.resolve_key(have, EnemyClipCatalog.KEY_STUN) == EnemyClipCatalog.KEY_HURT
			and EnemyClipCatalog.resolve_key(have, EnemyClipCatalog.KEY_TELEGRAPH) == EnemyClipCatalog.KEY_ATTACK
			and EnemyClipCatalog.resolve_key(have, EnemyClipCatalog.KEY_DASH) == EnemyClipCatalog.KEY_RUN
			and EnemyClipCatalog.resolve_key(have, EnemyClipCatalog.KEY_HURT) == EnemyClipCatalog.KEY_HURT,
		"why": "",
	})
	var empty := func(_key: StringName) -> bool: return false
	results.append({
		"name": "resolve_key: empty map yields empty (keep the current clip)",
		"passed": EnemyClipCatalog.resolve_key(empty, EnemyClipCatalog.KEY_STUN) == &""
			and EnemyClipCatalog.resolve_key(empty, EnemyClipCatalog.KEY_TELEGRAPH) == &"",
		"why": "",
	})
	var fwd := EnemyClipCatalog.directional_dash(Vector3(0, 0, -1), Vector3(0, 0, -1))
	var back := EnemyClipCatalog.directional_dash(Vector3(0, 0, -1), Vector3(0, 0, 1))
	var right := EnemyClipCatalog.directional_dash(Vector3(0, 0, -1), Vector3(1, 0, 0))
	var left := EnemyClipCatalog.directional_dash(Vector3(0, 0, -1), Vector3(-1, 0, 0))
	results.append({
		"name": "directional_dash matches HeroRigContract (Godot -Z forward)",
		"passed": fwd == &"Dodge_Forward" and back == &"Dodge_Backward"
			and right == &"Dodge_Right" and left == &"Dodge_Left",
		"why": "f=%s b=%s r=%s l=%s" % [String(fwd), String(back), String(right), String(left)],
	})
	results.append({
		"name": "resume_after_one_shot returns run for chase, death for dead",
		"passed": EnemyClipCatalog.resume_after_one_shot(&"chase") == EnemyClipCatalog.KEY_RUN
			and EnemyClipCatalog.resume_after_one_shot(&"dead") == EnemyClipCatalog.KEY_DEATH
			and EnemyClipCatalog.resume_after_one_shot(&"ranged") == EnemyClipCatalog.KEY_CAST
			and EnemyClipCatalog.resume_after_one_shot(&"stunned") == EnemyClipCatalog.KEY_STUN,
		"why": "",
	})
	results.append({
		"name": "hip_lock matches hips/pelvis/root and locomotion only",
		"passed": EnemyClipCatalog.hip_lock_bone_match("Armature/Hips")
			and EnemyClipCatalog.hip_lock_bone_match("Root")
			and not EnemyClipCatalog.hip_lock_bone_match("Hand.R")
			and EnemyClipCatalog.should_lock_hips(EnemyClipCatalog.KEY_RUN)
			and not EnemyClipCatalog.should_lock_hips(EnemyClipCatalog.KEY_DEATH),
		"why": "",
	})
	results.append({
		"name": "loop_mode_for: locomotion loops, one-shots do not",
		"passed": EnemyClipCatalog.loop_mode_for(EnemyClipCatalog.KEY_IDLE) == 1
			and EnemyClipCatalog.loop_mode_for(EnemyClipCatalog.KEY_DEATH) == 0,
		"why": "",
	})


static func _voice_bank_tokens(results: Array) -> void:
	var bank := VoiceBank.new()
	bank.token_base = 100
	bank.players = [null, null, null, null]
	bank.cues = [&"", &"", &"", &""]
	bank.fades = [{}, {}, {}, {}]
	results.append({
		"name": "VoiceBank tokens are namespaced from token_base",
		"passed": bank.token_of(0) == 100 and bank.token_of(3) == 103
			and bank.index_of_token(102) == 2
			and bank.owns_token(100)
			and not bank.owns_token(5)
			and bank.index_of_token(5) == -1,
		"why": "",
	})
	results.append({
		"name": "UI / spatial token bases do not collide with the 2D SFX 0..15 pool",
		"passed": VoiceBank.new().token_base == 0
			and SpatialVoicePool.TOKEN_BASE >= 200
			and SpatialVoicePool.MAX_VOICES == 16,
		"why": "spatial_base=%d" % SpatialVoicePool.TOKEN_BASE,
	})
	results.append({
		"name": "AudioConfig world cues are SFX, never UI",
		"passed": AudioConfig.is_world_cue(&"enemy_hit")
			and AudioConfig.is_world_cue(&"enemy_explosion")
			and not AudioConfig.is_world_cue(&"ui_confirm")
			and not AudioConfig.is_world_cue(&"player_shot")
			and AudioConfig.is_ui_bus(&"UI")
			and AudioConfig.is_music_bus(&"Music")
			and not AudioConfig.is_ui_bus(&"SFX"),
		"why": "",
	})
	var skill := AudioConfig.for_cue(&"skill_cast")
	var ui := AudioConfig.for_cue(&"ui_confirm")
	results.append({
		"name": "skill_cast stays on SFX (does not share the UI bus with confirm)",
		"passed": skill.bus == &"SFX" and ui.bus == &"UI" and skill.max_voices == 2,
		"why": "skill=%s ui=%s" % [String(skill.bus), String(ui.bus)],
	})
	var stem := AudioConfig.for_cue(&"music_battle_l2")
	results.append({
		"name": "stem ids are Music-bus and validate clean",
		"passed": stem.bus == &"Music" and stem.validate().is_empty(),
		"why": str(stem.validate()),
	})
