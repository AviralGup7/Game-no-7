class_name CameraAutoFollowController
extends RefCounted

## Elden Ring / Dark Souls style auto-follow – gentle, with deadzone and toward-camera suppression.
## Never fights the player when strafing or walking toward the camera.

var sustain_timer := 0.0
var is_active := false
var manual_cooldown := 0.0

var _profile: CameraProfile = null


func setup(profile: CameraProfile) -> void:
	_profile = profile


func set_profile(profile: CameraProfile) -> void:
	_profile = profile


func notify_manual_input() -> void:
	if _profile == null:
		return
	manual_cooldown = _profile.manual_orbit_cooldown
	is_active = false
	sustain_timer = 0.0


func tick(delta: float, velocity_tracker: CameraVelocityTracker, orbit: CameraOrbitState, cam_pos: Vector3, focus_pos: Vector3) -> void:
	if _profile == null or orbit == null or velocity_tracker == null:
		is_active = false
		return

	if not _profile.auto_follow_enabled:
		is_active = false
		return

	if manual_cooldown > 0.0:
		manual_cooldown = maxf(manual_cooldown - delta, 0.0)
		sustain_timer = 0.0
		is_active = false
		return

	if velocity_tracker.speed < 0.6:
		sustain_timer = maxf(sustain_timer - delta * 1.5, 0.0)
		is_active = false
		return

	sustain_timer += delta
	if sustain_timer < _profile.auto_follow_delay:
		is_active = false
		return

	var move_dir := velocity_tracker.move_dir
	move_dir.y = 0.0
	if move_dir.length_squared() < 0.0001:
		is_active = false
		return
	move_dir = move_dir.normalized()
	var move_yaw := CameraMath.yaw_from_direction(move_dir)

	var diff := CameraMath.angle_difference(orbit.current_yaw, move_yaw)
	if absf(diff) < deg_to_rad(_profile.auto_follow_deadzone_deg):
		is_active = false
		return

	# Toward-camera suppression. Authored as a *positive* dot threshold (0.25 =
	# moving clearly toward the lens). Negative legacy values are treated as the
	# documented 0.25 so a sign typo cannot disable follow entirely.
	var to_cam := cam_pos - focus_pos
	to_cam.y = 0.0
	if to_cam.length_squared() > 0.0001:
		to_cam = to_cam.normalized()
		var toward := move_dir.dot(to_cam)
		var toward_gate := _profile.auto_follow_toward_camera_threshold
		if toward_gate < 0.0:
			toward_gate = 0.25
		if toward > toward_gate:
			is_active = false
			return
		# Strafe – reduce speed
		if absf(toward) < 0.35:
			var suppression := _profile.auto_follow_strafe_suppression
			orbit.target_yaw = CameraMath.lerp_angle_weighted(
				orbit.target_yaw, move_yaw,
				clampf(delta * _profile.auto_follow_speed * suppression, 0.0, 1.0)
			)
			is_active = true
			return

	var follow_speed := _profile.auto_follow_speed
	var speed_scale := clampf(absf(diff) / deg_to_rad(90.0), 0.3, 1.5)
	orbit.target_yaw = CameraMath.lerp_angle_weighted(
		orbit.target_yaw, move_yaw,
		clampf(delta * follow_speed * speed_scale, 0.0, 1.0)
	)
	is_active = true


func reset() -> void:
	sustain_timer = 0.0
	is_active = false
	manual_cooldown = 0.0
