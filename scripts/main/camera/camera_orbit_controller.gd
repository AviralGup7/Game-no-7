class_name CameraOrbitController
extends RefCounted

## Handles manual orbit input and smoothing of yaw/pitch/distance.
## Delegates auto-follow to CameraAutoFollowController, lock-on yaw to a gentle
## lerp that keeps the locked enemy ahead of the player, and never fights the
## arena boom clamp (distance is profile-capped; walls are CameraMath's job).

var orbit: CameraOrbitState = null
var input_handler: CameraInputHandler = null
var auto_follow: CameraAutoFollowController = null
var _profile: CameraProfile = null


func setup(profile: CameraProfile, orbit_state: CameraOrbitState, input: CameraInputHandler, auto: CameraAutoFollowController) -> void:
	_profile = profile
	orbit = orbit_state
	input_handler = input
	auto_follow = auto


func set_profile(profile: CameraProfile) -> void:
	_profile = profile


func tick(delta: float, velocity_tracker: CameraVelocityTracker, cam_pos: Vector3, focus_pos: Vector3, framing: CameraFramingController, mode: CameraModeController, reduced_motion: bool, lock_pos: Vector3 = Vector3.ZERO) -> void:
	if _profile == null or orbit == null:
		return

	var manual := input_handler.gather(delta) if input_handler != null else Vector2.ZERO
	var has_manual := manual.length_squared() > 0.0001

	if has_manual:
		if auto_follow != null:
			auto_follow.notify_manual_input()
		# gather() already returns this-frame degrees. Write current AND target
		# so a finger swipe turns the lens with the thumb instead of sitting in
		# the yaw-smoothing lag (exp_weight(3.2) is ~5% per 60 Hz frame).
		var yaw_delta := deg_to_rad(manual.x)
		var pitch_delta := deg_to_rad(manual.y)
		orbit.target_yaw -= yaw_delta
		orbit.current_yaw -= yaw_delta
		orbit.target_pitch += pitch_delta
		orbit.current_pitch += pitch_delta
	elif mode != null and mode.is_locked() and CameraMath.is_finite_v3(lock_pos):
		# Zelda-style: sit behind the player, looking toward the lock. Manual
		# orbit above still wins for the frame, so the right stick is not trapped.
		var to_lock := lock_pos - focus_pos
		to_lock.y = 0.0
		if to_lock.length_squared() > 0.0001:
			var lock_yaw := CameraMath.yaw_from_direction(to_lock)
			orbit.target_yaw = CameraMath.lerp_angle_weighted(
				orbit.target_yaw, lock_yaw, clampf(delta * 4.0, 0.0, 1.0)
			)
	elif auto_follow != null:
		auto_follow.tick(delta, velocity_tracker, orbit, cam_pos, focus_pos)

	var pitch_min := deg_to_rad(_profile.min_pitch_deg)
	var pitch_max := deg_to_rad(_profile.max_pitch_deg)
	orbit.target_pitch = clampf(orbit.target_pitch, pitch_min, pitch_max)
	orbit.current_pitch = clampf(orbit.current_pitch, pitch_min, pitch_max)

	var base_dist := _profile.get_clamped_distance()
	if mode != null:
		# Mode controller already blends from the previous multiplier to the new one.
		base_dist *= mode.get_mode_distance_multiplier()

	var combat_boost := 0.0
	if framing != null:
		combat_boost = framing.get_combat_distance_boost()

	orbit.target_distance = clampf(base_dist + combat_boost, _profile.min_distance, _profile.max_distance)

	var yaw_smooth := _profile.yaw_smoothing
	var pitch_smooth := _profile.pitch_smoothing
	if reduced_motion:
		yaw_smooth = _profile.reduced_motion_smoothing
		pitch_smooth = _profile.reduced_motion_smoothing

	var yaw_w := CameraMath.exp_weight(yaw_smooth, delta)
	var pitch_w := CameraMath.exp_weight(pitch_smooth, delta)

	orbit.current_yaw = CameraMath.lerp_angle_weighted(orbit.current_yaw, orbit.target_yaw, yaw_w)
	orbit.current_pitch = lerpf(orbit.current_pitch, orbit.target_pitch, pitch_w)

	var dist_target := orbit.target_distance
	var dist_smooth := _profile.distance_smoothing_out
	if orbit.collision_distance < orbit.current_distance - 0.05:
		dist_target = orbit.collision_distance
		dist_smooth = _profile.distance_smoothing_in

	if reduced_motion:
		dist_smooth = _profile.reduced_motion_smoothing

	var dist_w := CameraMath.exp_weight(dist_smooth, delta)
	orbit.current_distance = lerpf(orbit.current_distance, dist_target, dist_w)
	orbit.current_distance = clampf(orbit.current_distance, _profile.min_distance, _profile.max_distance)


func reset_orbit(facing_yaw: float) -> void:
	if orbit == null:
		return
	orbit.snap_to_facing(facing_yaw, _profile)
	if auto_follow != null:
		auto_follow.reset()
	if input_handler != null:
		input_handler.reset()


func set_target_distance(dist: float) -> void:
	if orbit != null:
		orbit.target_distance = clampf(
			dist,
			_profile.min_distance if _profile else 1.0,
			_profile.max_distance if _profile else 20.0
		)
