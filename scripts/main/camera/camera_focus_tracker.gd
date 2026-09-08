class_name CameraFocusTracker
extends RefCounted

## Focus point with predictive look-ahead, separate vertical damping.
## Inspired by Zelda BOTW + Uncharted: focus = player + look_height + velocity*预测 + move_dir*look_ahead.

var focus_point := Vector3.ZERO
var desired_focus := Vector3.ZERO

var _profile: CameraProfile = null
var _velocity_tracker: CameraVelocityTracker = null

func setup(profile: CameraProfile, velocity_tracker: CameraVelocityTracker, initial_focus: Vector3) -> void:
	_profile = profile
	_velocity_tracker = velocity_tracker
	focus_point = initial_focus
	desired_focus = initial_focus

func set_profile(profile: CameraProfile) -> void:
	_profile = profile

func tick(target_pos: Vector3, delta: float, reduced_motion: bool = false) -> void:
	if _profile == null or _velocity_tracker == null:
		return

	var base_focus := target_pos + Vector3(0.0, _profile.look_height, 0.0)

	# Predictive + look-ahead
	var predictive := _velocity_tracker.velocity * _profile.predictive_factor
	var look_ahead := Vector3.ZERO
	if _velocity_tracker.speed > 0.5:
		look_ahead = _velocity_tracker.move_dir * _profile.look_ahead_distance * clampf(_velocity_tracker.speed / 6.0, 0.0, 1.0)

	desired_focus = base_focus + predictive + look_ahead

	# Separate H/V smoothing to reduce bobbing when jumping
	var horiz_smooth := _profile.follow_smoothing
	var vert_smooth := _profile.focus_height_lerp
	if reduced_motion:
		horiz_smooth = _profile.reduced_motion_smoothing
		vert_smooth = _profile.reduced_motion_smoothing

	var w_h := CameraMath.exp_weight(horiz_smooth, delta)
	var w_v := CameraMath.exp_weight(vert_smooth, delta)

	focus_point.x = lerpf(focus_point.x, desired_focus.x, w_h)
	focus_point.z = lerpf(focus_point.z, desired_focus.z, w_h)
	focus_point.y = lerpf(focus_point.y, desired_focus.y, w_v)

	if focus_point == Vector3.ZERO:
		focus_point = desired_focus

func snap_to(pos: Vector3) -> void:
	focus_point = pos
	desired_focus = pos
