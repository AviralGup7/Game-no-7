extends Node
class_name CharacterController

## Converts movement intent into grounded, collision-aware motion and facing for the
## owning CharacterBody3D. Pure-ish with respect to timing: physics uses delta so a
## fixed/fake clock produces deterministic results.

@export var move_speed: float = 6.0
@export var acceleration: float = 24.0
@export var deceleration: float = 30.0
@export var gravity: float = 18.0

var _last_move_input := Vector2.ZERO
var _owner_body: CharacterBody3D = null


func _ready() -> void:
	_owner_body = get_parent() as CharacterBody3D
	if _owner_body == null:
		push_warning("CharacterController parent is not a CharacterBody3D")


## Advance the body for one physics step. move_input is a normalized joystick/axis
## Vector2 in screen space (x=strafe, y=forward as perceived on screen).
func tick(move_input: Vector2, delta: float) -> void:
	if _owner_body == null:
		return
	_last_move_input = _sanitize(move_input)

	var vel := _owner_body.velocity
	if not _owner_body.is_on_floor():
		vel.y -= gravity * delta

	var dir := _screen_dir_to_world(_last_move_input)
	var target_h := dir * move_speed
	if dir.length_squared() > 0.001:
		vel.x = move_toward(vel.x, target_h.x, acceleration * delta)
		vel.z = move_toward(vel.z, target_h.z, acceleration * delta)
		_facing(dir)
	else:
		vel.x = move_toward(vel.x, 0.0, deceleration * delta)
		vel.z = move_toward(vel.z, 0.0, deceleration * delta)

	_owner_body.velocity = vel
	_owner_body.move_and_slide()


## Horizontal ground movement basis relative to the camera rig yaw (screen-forwards
## maps to camera forward). Returns a normalized Vector3 in world XZ.
func _screen_dir_to_world(v: Vector2) -> Vector3:
	var cam_yaw := _camera_yaw()
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var dir3 := (forward * v.y + right * v.x)
	if dir3.length_squared() > 0.0001:
		dir3 = dir3.normalized()
	return dir3


func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return 0.0
	return cam.global_transform.basis.get_euler().y


func _facing(dir: Vector3) -> void:
	# Rotate the visual root toward the movement direction smoothly.
	var visual := _owner_body.get_node_or_null("VisualRoot")
	if visual == null or dir.length_squared() < 0.001:
		return
	var target := Transform3D(visual.global_transform)
	var target_basis := target.basis.looking_at(dir, Vector3.UP)
	var target_quat := target_basis.get_rotation_quaternion()
	var current_quat := visual.global_transform.basis.get_rotation_quaternion()
	# Rotation applied in _physics in player; here we set an aim hint that player uses.
	_owner_body.set_meta("face_quat", target_quat)
	_owner_body.set_meta("face_current", current_quat)


func _sanitize(v: Vector2) -> Vector2:
	var len_sq := v.length_squared()
	if len_sq > 1.0:
		return v.normalized()
	return v


func is_moving() -> bool:
	return _last_move_input.length_squared() > 0.001


func set_move_speed(value: float) -> void:
	move_speed = maxf(value, 0.0)


func get_debug_snapshot() -> Dictionary:
	return {
		"move_input": Vector2(_last_move_input.x, _last_move_input.y),
		"is_moving": is_moving(),
		"move_speed": move_speed,
	}
