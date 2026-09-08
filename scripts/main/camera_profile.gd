class_name CameraProfile
extends Resource

## Data-driven third-person camera tuning. One profile per arena / mode / accessory
## so future arenas, bosses, or accessibility modes change the camera without code
## edits. Validated centrally so profiles with impossible values never apply.

@export var profile_id: StringName = &"default"
@export var distance: float = 8.0
@export var height: float = 4.0
@export var field_of_view: float = 70.0
@export var follow_smoothing: float = 6.0
@export var look_height: float = 1.6
@export var pitch_degrees: float = 20.0
@export var collision_radius: float = 0.3
@export var reduced_motion_smoothing: float = 2.0
@export var max_shake_amplitude: float = 1.0

const MIN_DISTANCE: float = 2.0
const MAX_DISTANCE: float = 30.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(profile_id).is_empty():
		problems.append("profile_id is empty")
	if distance < MIN_DISTANCE or distance > MAX_DISTANCE:
		problems.append("distance out of safe range")
	if height < 0.5 or height > 20.0:
		problems.append("height out of safe range")
	if field_of_view < 40.0 or field_of_view > 110.0:
		problems.append("field_of_view out of safe range")
	if follow_smoothing <= 0.0:
		problems.append("follow_smoothing must be > 0")
	if look_height < 0.0:
		problems.append("look_height cannot be negative")
	if pitch_degrees < -89.0 or pitch_degrees > 89.0:
		problems.append("pitch_degrees must be within [-89, 89]")
	return problems

## Hardened: clamp camera profile values.
func _validated_profile() -> void:
    if not is_finite(fov) or fov <= 0.0:
        fov = 75.0
    fov = clampf(fov, 10.0, 120.0)
    if not is_finite(distance) or distance <= 0.0:
        distance = 10.0
    distance = clampf(distance, 1.0, 50.0)

