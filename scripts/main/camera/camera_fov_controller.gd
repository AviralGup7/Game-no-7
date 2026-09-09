class_name CameraFovController
extends RefCounted

## Dynamic FOV – base + speed boost + combat boost + mode multiplier, smoothed.
## God of War / Uncharted style: slight FOV increase on sprint, wider for boss.

var current_fov: float = 62.0
var _profile: CameraProfile = null

func setup(profile: CameraProfile) -> void:
	_profile = profile
	if profile != null:
		current_fov = profile.field_of_view

func set_profile(profile: CameraProfile) -> void:
	_profile = profile

func tick(delta: float, velocity_tracker: CameraVelocityTracker, framing: CameraFramingController, mode: CameraModeController, camera: Camera3D, reduced_motion: bool) -> void:
	if _profile == null or camera == null:
		return

	var base_fov := _profile.field_of_view
	var target_fov := base_fov

	# Speed boost
	if velocity_tracker != null and velocity_tracker.speed > _profile.fov_sprint_threshold:
		var boost := clampf((velocity_tracker.speed - _profile.fov_sprint_threshold) * _profile.fov_speed_boost * 0.18, 0.0, _profile.fov_max_boost)
		target_fov += boost

	# Combat boost
	if framing != null:
		target_fov += framing.get_combat_fov_boost()

	# Mode multiplier (boss = wider, locked = narrower)
	if mode != null:
		var mult := mode.get_mode_fov_multiplier()
		# Blend toward multiplied FOV based on mode blend factor
		var blend := mode.get_blend_factor()
		var mode_fov := base_fov * mult
		target_fov = lerpf(target_fov, mode_fov + (target_fov - base_fov), blend) if mult != 1.0 else target_fov
		# Simpler: lerp between base-influenced and mode-influenced
		if mult != 1.0:
			target_fov = lerpf(base_fov, base_fov * mult, blend) + (target_fov - base_fov)

	var smoothing := _profile.fov_smoothing
	if reduced_motion:
		smoothing = _profile.reduced_motion_smoothing

	var weight := CameraMath.exp_weight(smoothing, delta)
	current_fov = _bounded(lerpf(current_fov, target_fov, weight))
	camera.fov = current_fov


## A non-finite or out-of-range FOV makes an invalid projection matrix, which the
## renderer cannot recover from mid-frame and which also corrupts every
## `Camera3D.unproject_position()` the HUD performs. Hold the last good value instead;
## the limits are Godot's own for Camera3D.fov, so authored values are untouched.
func _bounded(fov: float) -> float:
	if not is_finite(fov):
		return current_fov if is_finite(current_fov) else 45.0
	return clampf(fov, 1.0, 179.0)


func snap_to(profile_fov: float) -> void:
	current_fov = 45.0 if not is_finite(profile_fov) else clampf(profile_fov, 1.0, 179.0)
