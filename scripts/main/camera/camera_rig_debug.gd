class_name CameraRigDebug
extends RefCounted

## One read-only render of the camera rig for the debug overlay (mirrors
## EnemyDebugView / Player.get_debug_snapshot). Extracted from CameraRig so the
## diagnostics do not sit in the middle of the per-frame coordinator: adding a field
## here touches no camera code.
##
## This is the one place allowed to read across the rig's modules — it copies values
## out and never mutates or stores a reference.


static func snapshot(rig: CameraRig) -> Dictionary:
	var profile := rig._profile
	var profile_dict: Dictionary = {}
	if profile != null:
		profile_dict = {
			"profile_id": String(profile.profile_id),
			"distance": profile.distance,
			"height": profile.height,
			"current_distance": rig._orbit_state.current_distance,
			"target_distance": rig._orbit_state.target_distance,
			"collision_distance": rig._orbit_state.collision_distance,
			"is_colliding": rig._collision.is_colliding,
			"yaw_deg": rad_to_deg(rig._orbit_state.current_yaw),
			"pitch_deg": rad_to_deg(rig._orbit_state.current_pitch),
			"fov": rig._fov.current_fov,
			"auto_follow": rig._auto_follow.is_active,
			"manual_cooldown": rig._auto_follow.manual_cooldown,
			"move_sustain": rig._auto_follow.sustain_timer,
			"mode": rig._mode.current_mode,
			"enemy_count": rig._framing.get_enemy_count(),
			"combat_boost": rig._framing.get_combat_distance_boost(),
			"solver": rig._collision.get_debug_snapshot(),
			"interpolated_target": rig._uses_interpolated_target,
		}
	return {
		"enabled": rig._enabled,
		"has_target": rig._target != null and is_instance_valid(rig._target),
		"profile": profile_dict,
		"shake_remaining": rig._shake.get_remaining() if rig._shake != null else 0.0,
		"position": rig.global_position,
		"focus": rig._focus.focus_point,
		"target_velocity": rig._velocity.velocity,
		"target_speed": rig._velocity.speed,
		"modules": {
			"input": rig._input_handler != null,
			"velocity": rig._velocity != null,
			"focus": rig._focus != null,
			"orbit": rig._orbit_state != null,
			"collision": rig._collision != null,
			"framing": rig._framing != null,
			"fov": rig._fov != null,
			"shake": rig._shake != null,
			"mode": rig._mode != null,
		},
	}
