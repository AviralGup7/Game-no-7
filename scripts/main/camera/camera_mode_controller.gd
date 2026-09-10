class_name CameraModeController
extends RefCounted

## Handles camera modes – explore, combat, boss, locked – with smooth blending.
## Inspired by God of War (no cuts, but FOV/distance shift) and Zelda lock-on.
## Uses profile multipliers for data-driven tuning.
##
## Unlocking lock-on restores the mode we entered lock from (boss stays boss).
## Multipliers lerp from the *previous* values so leaving combat does not snap.

enum Mode {
	EXPLORE,
	COMBAT,
	BOSS,
	LOCKED, # Z-target lock-on
}

var current_mode: Mode = Mode.EXPLORE
var _profile: CameraProfile = null
var _target_profile: CameraProfile = null
var _blend_timer := 0.0
var _blend_duration := 0.6

var _lock_target: Node3D = null
var _is_locked := false
var _mode_before_lock: Mode = Mode.EXPLORE
var _from_fov_mult := 1.0
var _from_dist_mult := 1.0
var _to_fov_mult := 1.0
var _to_dist_mult := 1.0


func setup(profile: CameraProfile) -> void:
	_profile = profile
	_target_profile = profile


func set_profile(profile: CameraProfile) -> void:
	_profile = profile
	if _target_profile == null:
		_target_profile = profile


func set_mode(new_mode: Mode, blend_duration: float = -1.0) -> void:
	if new_mode != Mode.LOCKED:
		_mode_before_lock = new_mode
	if new_mode == current_mode:
		return
	_from_fov_mult = get_mode_fov_multiplier()
	_from_dist_mult = get_mode_distance_multiplier()
	current_mode = new_mode
	if blend_duration < 0.0 and _profile != null:
		match new_mode:
			Mode.EXPLORE:
				_blend_duration = _profile.mode_blend_duration_explore
			Mode.COMBAT:
				_blend_duration = _profile.mode_blend_duration_combat
			Mode.BOSS:
				_blend_duration = _profile.mode_blend_duration_boss
			Mode.LOCKED:
				_blend_duration = _profile.mode_blend_duration_locked
			_:
				_blend_duration = 0.6
	else:
		_blend_duration = blend_duration if blend_duration >= 0.0 else 0.6
	_blend_timer = 0.0
	_to_fov_mult = _raw_fov(new_mode)
	_to_dist_mult = _raw_dist(new_mode)


func set_lock_target(target: Node3D) -> void:
	_lock_target = target
	_is_locked = target != null and is_instance_valid(target)
	if _is_locked:
		set_mode(Mode.LOCKED, _profile.mode_blend_duration_locked if _profile != null else 0.35)
	else:
		set_mode(_mode_before_lock, _profile.mode_blend_duration_explore if _profile != null else 0.5)


func tick(delta: float) -> void:
	if _blend_timer < _blend_duration:
		_blend_timer += delta


func get_blend_factor() -> float:
	if _blend_duration <= 0.0:
		return 1.0
	return clampf(_blend_timer / _blend_duration, 0.0, 1.0)


func is_locked() -> bool:
	return _is_locked and _lock_target != null and is_instance_valid(_lock_target)


func get_lock_target() -> Node3D:
	return _lock_target


func get_mode_fov_multiplier() -> float:
	return lerpf(_from_fov_mult, _to_fov_mult, get_blend_factor())


func get_mode_distance_multiplier() -> float:
	return lerpf(_from_dist_mult, _to_dist_mult, get_blend_factor())


func _raw_fov(mode: Mode) -> float:
	if _profile == null:
		match mode:
			Mode.BOSS: return 1.08
			Mode.COMBAT: return 1.04
			Mode.LOCKED: return 0.96
			_: return 1.0
	match mode:
		Mode.BOSS:
			return _profile.boss_fov_multiplier
		Mode.COMBAT:
			return _profile.combat_fov_multiplier
		Mode.LOCKED:
			return _profile.locked_fov_multiplier
		_:
			return 1.0


func _raw_dist(mode: Mode) -> float:
	if _profile == null:
		match mode:
			Mode.BOSS: return 1.25
			Mode.COMBAT: return 1.1
			Mode.LOCKED: return 0.85
			_: return 1.0
	match mode:
		Mode.BOSS:
			return _profile.boss_distance_multiplier
		Mode.COMBAT:
			return _profile.combat_distance_multiplier
		Mode.LOCKED:
			return _profile.locked_distance_multiplier
		_:
			return 1.0


func reset() -> void:
	current_mode = Mode.EXPLORE
	_mode_before_lock = Mode.EXPLORE
	_blend_timer = 0.0
	_lock_target = null
	_is_locked = false
	_from_fov_mult = 1.0
	_from_dist_mult = 1.0
	_to_fov_mult = 1.0
	_to_dist_mult = 1.0
