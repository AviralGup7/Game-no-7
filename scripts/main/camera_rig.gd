extends Node3D
class_name CameraRig

## Third-person follow camera. Smoothly follows a target, looks at the player, avoids
## clipping terrain via a short downward/outward ray, supports data-driven profiles
## and bounded shake, and honours reduced-motion settings.

const CAMERA_GROUP := &"camera_rig"

var _target: Node3D = null
var _profile: CameraProfile = null
var _camera: Camera3D = null
var _shake_remaining := 0.0
var _shake_amplitude := 0.0
var _enabled := false
var _reduced_motion := false
var _base_cam_pos := Vector3.ZERO


func _ready() -> void:
	add_to_group(String(CAMERA_GROUP))
	_camera = _find_camera()
	if _camera != null:
		_camera.make_current()
		_base_cam_pos = _camera.position
	_profile = ContentRegistry.get_camera_profile(&"default")
	if _profile == null:
		_profile = CameraProfile.new()
	_refresh_settings()


func _find_camera() -> Camera3D:
	var found := get_node_or_null("Camera3D") as Camera3D
	return found


func set_target(target: Node3D) -> void:
	_target = target
	_enabled = target != null
	if _enabled and _target != null:
		# Snap immediately on attach to avoid a long glide at run start.
		_apply_follow(1.0)


func set_camera_profile(profile: CameraProfile) -> void:
	if profile != null:
		_profile = profile
	_refresh_settings()


func add_shake(amplitude: float, duration: float) -> void:
	if _profile == null:
		return
	if _reduced_motion:
		return
	_shake_amplitude = clampf(amplitude, 0.0, _profile.max_shake_amplitude)
	_shake_remaining = maxf(_shake_remaining, duration)


func reset_transform() -> void:
	_shake_remaining = 0.0
	_shake_amplitude = 0.0
	if _target != null:
		_apply_follow(1.0)


func _process(delta: float) -> void:
	if not _enabled or _target == null:
		return
	if not is_instance_valid(_target):
		_enabled = false
		return
	var smoothing := _profile.follow_smoothing if _profile != null else 6.0
	_apply_follow(clampf(delta * smoothing, 0.0, 1.0))
	_update_shake(delta)


func _apply_follow(weight: float) -> void:
	if _profile == null or _target == null:
		return
	var desired := _desired_camera_position()
	# Smoothly move the whole rig to the desired point.
	global_position = global_position.lerp(desired, weight)
	if _camera != null:
		var look := _target.global_position + Vector3(0.0, _profile.look_height, 0.0)
		_camera.global_transform = _camera.global_transform.looking_at(look, Vector3.UP)
		_camera.fov = _profile.field_of_view


func _desired_camera_position() -> Vector3:
	var target_pos := _target.global_position
	# Camera sits behind/above the player by profile distance & height, pitched down.
	var offset := Vector3(0.0, _profile.height, _profile.distance)
	var base := target_pos + offset
	# Simple clip guard: if a wall sits between target and camera, pull camera in.
	var blocked := _raycast_blocked(target_pos, base)
	if blocked != Vector3.INF:
		var dir := (base - target_pos).normalized()
		base = blocked - dir * 0.5
	return base


func _raycast_blocked(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result := space.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF
	return result.get("position", Vector3.INF)


func _update_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_remaining <= 0.0:
		# Restore the rig-relative placement so one shake can't drift the lens.
		if _camera.position != _base_cam_pos:
			_camera.position = _base_cam_pos
		return
	_shake_remaining = maxf(_shake_remaining - delta, 0.0)
	var strength := _shake_amplitude * (_shake_remaining / maxf(_shake_remaining + 0.1, 0.001))
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength
	_camera.position = _base_cam_pos + offset


func _refresh_settings() -> void:
	_reduced_motion = SaveManager.get_settings().reduced_motion


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func get_debug_snapshot() -> Dictionary:
	var p: Dictionary = {}
	if _profile != null:
		p = {
			"profile_id": String(_profile.profile_id),
			"distance": _profile.distance,
			"height": _profile.height,
		}
	return {
		"enabled": _enabled,
		"has_target": _target != null and is_instance_valid(_target),
		"profile": p,
		"shake_remaining": _shake_remaining,
		"position": global_position,
	}

## Hardened: validate camera rig lerp.
func _validated_lerp_weight(w: float, delta: float) -> float:
	if not is_finite(w) or w < 0.0:
		w = 0.1
	if not is_finite(delta) or delta <= 0.0:
		delta = 0.016
	return clampf(w * delta * 60.0, 0.0, 1.0)

