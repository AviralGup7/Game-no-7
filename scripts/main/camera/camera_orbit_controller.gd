class_name CameraOrbitController
extends RefCounted

## Handles manual orbit input and smoothing of yaw/pitch/distance.
## Delegates auto-follow decision to CameraAutoFollowController.
## Now also respects mode distance multipliers and combat framing boost.

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

func tick(delta: float, velocity_tracker: CameraVelocityTracker, cam_pos: Vector3, focus_pos: Vector3, framing: CameraFramingController, mode: CameraModeController, reduced_motion: bool) -> void:
	if _profile == null or orbit == null:
		return

	# Manual
	var manual := input_handler.gather(delta) if input_handler != null else Vector2.ZERO
	var has_manual := manual.length_squared() > 0.0001

	if has_manual:
		auto_follow.notify_manual_input()
		orbit.target_yaw -= manual.x * deg_to_rad(_profile.orbit_speed_deg) * delta * 6.0
		orbit.target_pitch += manual.y * deg_to_rad(_profile.orbit_speed_deg) * delta * 6.0
		orbit.target_pitch = clampf(orbit.target_pitch, deg_to_rad(_profile.min_pitch_deg), deg_to_rad(_profile.max_pitch_deg))

	# Auto follow
	auto_follow.tick(delta, velocity_tracker, orbit, cam_pos, focus_pos)

	# Compute desired target distance with mode + combat boosts
	var base_dist := _profile.get_clamped_distance()
	var mode_mult := 1.0
	var blend := 1.0
	if mode != null:
		mode_mult = mode.get_mode_distance_multiplier()
		blend = mode.get_blend_factor()
		# Blend base toward mode-multiplied
		if mode_mult != 1.0:
			base_dist = lerpf(_profile.get_clamped_distance(), _profile.get_clamped_distance() * mode_mult, blend)

	var combat_boost := 0.0
	if framing != null:
		combat_boost = framing.get_combat_distance_boost()

	orbit.target_distance = clampf(base_dist + combat_boost, _profile.min_distance, _profile.max_distance)

	# Smooth
	var yaw_smooth := _profile.yaw_smoothing
	var pitch_smooth := _profile.pitch_smoothing
	if reduced_motion:
		yaw_smooth = _profile.reduced_motion_smoothing
		pitch_smooth = _profile.reduced_motion_smoothing

	var yaw_w := CameraMath.exp_weight(yaw_smooth, delta)
	var pitch_w := CameraMath.exp_weight(pitch_smooth, delta)

	orbit.current_yaw = CameraMath.lerp_angle_weighted(orbit.current_yaw, orbit.target_yaw, yaw_w)
	orbit.current_pitch = lerpf(orbit.current_pitch, orbit.target_pitch, pitch_w)

	# Distance smoothing with in/out
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
	orbit.target_yaw = facing_yaw
	orbit.target_pitch = deg_to_rad(_profile.get_clamped_pitch_deg()) if _profile != null else orbit.target_pitch
	auto_follow.reset()
	input_handler.reset()

func set_target_distance(dist: float) -> void:
	if orbit != null:
		orbit.target_distance = clampf(dist, _profile.min_distance if _profile else 1.0, _profile.max_distance if _profile else 20.0)
