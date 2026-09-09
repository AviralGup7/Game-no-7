class_name CameraVelocityTracker
extends RefCounted

## Tracks target velocity, speed, move direction with smoothing and teleport guard.
## Used for predictive focus, FOV boost, auto-follow.

var velocity := Vector3.ZERO
var speed := 0.0
var move_dir := Vector3.ZERO
var last_position := Vector3.ZERO
var _smoothing := 8.0

func setup(initial_pos: Vector3, smoothing: float = 8.0) -> void:
	last_position = initial_pos
	_smoothing = smoothing
	velocity = Vector3.ZERO
	speed = 0.0
	move_dir = Vector3.ZERO

func tick(current_pos: Vector3, delta: float) -> void:
	var diff := current_pos - last_position
	# Teleport guard – snap if moved too far in one frame
	if diff.length_squared() > 100.0:
		velocity = Vector3.ZERO
		speed = 0.0
		last_position = current_pos
		return

	var raw_vel := diff / maxf(delta, 0.0001)
	var weight := CameraMath.exp_weight(_smoothing, delta)
	velocity = velocity.lerp(raw_vel, weight)
	speed = velocity.length()
	if speed > 0.3:
		move_dir = velocity.normalized()
	last_position = current_pos

func reset(pos: Vector3) -> void:
	last_position = pos
	velocity = Vector3.ZERO
	speed = 0.0
	move_dir = Vector3.ZERO
