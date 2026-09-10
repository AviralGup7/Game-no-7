class_name CameraOrbitState
extends RefCounted

## Holds current/target spherical orbit state – yaw, pitch, distance.
## Pure data, no logic, easy to blend between profiles.

var current_yaw: float = 0.0
var target_yaw: float = 0.0
var current_pitch: float = 0.55
var target_pitch: float = 0.55
var current_distance: float = 9.0
var target_distance: float = 9.0
var collision_distance: float = 9.0

func setup_from_profile(profile: CameraProfile, facing_yaw: float = 0.0) -> void:
	if profile == null:
		return
	current_distance = profile.get_clamped_distance()
	target_distance = current_distance
	collision_distance = current_distance
	current_pitch = deg_to_rad(profile.get_clamped_pitch_deg())
	target_pitch = current_pitch
	current_yaw = facing_yaw
	target_yaw = facing_yaw

func snap_to_facing(yaw: float, profile: CameraProfile) -> void:
	current_yaw = yaw
	target_yaw = yaw
	if profile != null:
		target_pitch = deg_to_rad(profile.get_clamped_pitch_deg())
		current_pitch = target_pitch
		target_distance = profile.get_clamped_distance()
		current_distance = target_distance
		collision_distance = target_distance
