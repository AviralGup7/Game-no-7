class_name EnemyLocomotion
extends RefCounted

## Enemy movement integration, extracted from EnemyBase. Owns gravity, the
## resistance-aware knockback impulse (+ its decay), velocity steering toward the
## AI's desired intent, arena-bound clamping, and stuck detection/recovery.
## The intent itself (desired_dir/desired_speed) stays public on EnemyBase where
## the AI states write it; this module only integrates it each physics step.

const GRAVITY := 18.0
const KNOCKBACK_DECAY := 18.0
const STUCK_NUDGE_DIST := 0.05

var _knockback := Vector3.ZERO
var _stuck_time := 0.0
var _last_position := Vector3.ZERO
var _acceleration := 8.0
var _bounds_half := -1.0    # -1 disables the arena clamp
var _bounds_margin := 0.5


func configure(acceleration: float, bounds_half: float, bounds_margin: float) -> void:
	_acceleration = acceleration
	_bounds_half = bounds_half
	_bounds_margin = bounds_margin


func set_bounds(half: float) -> void:
	_bounds_half = half


func get_bounds() -> float:
	return _bounds_half


func reset() -> void:
	_knockback = Vector3.ZERO
	_stuck_time = 0.0
	_last_position = Vector3.ZERO


func add_knockback(impulse: Vector3) -> void:
	_knockback += Vector3(impulse.x, 0.0, impulse.z)


## One physics step: gravity, knockback decay, steering, slide, clamp, stall.
## Pass detect_stall=false for steps where the AI did not run (stun freeze).
func integrate(body: CharacterBody3D, desired_dir: Vector3, desired_speed: float, slow_factor: float, delta: float, detect_stall: bool = true) -> void:
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * delta
	if _knockback.length_squared() > 0.0:
		_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	var wish_x := desired_dir.x * desired_speed * slow_factor + _knockback.x
	var wish_z := desired_dir.z * desired_speed * slow_factor + _knockback.z
	body.velocity.x = move_toward(body.velocity.x, wish_x, _acceleration * delta)
	body.velocity.z = move_toward(body.velocity.z, wish_z, _acceleration * delta)
	body.move_and_slide()
	_clamp_to_bounds(body)
	if detect_stall:
		_detect_stall(body, desired_dir, desired_speed, delta)


func _clamp_to_bounds(body: CharacterBody3D) -> void:
	if _bounds_half < 0.0:
		return
	var limit := _bounds_half - _bounds_margin
	var p := body.global_position
	var changed := false
	if p.x < -limit:
		p.x = -limit
		changed = true
	elif p.x > limit:
		p.x = limit
		changed = true
	if p.z < -limit:
		p.z = -limit
		changed = true
	elif p.z > limit:
		p.z = limit
		changed = true
	if changed:
		body.global_position = p
		body.velocity.x = 0.0
		body.velocity.z = 0.0


func _detect_stall(body: CharacterBody3D, desired_dir: Vector3, desired_speed: float, delta: float) -> void:
	if desired_speed <= 0.0:
		_stuck_time = 0.0
		_last_position = body.global_position
		return
	var moved := body.global_position.distance_to(_last_position)
	_last_position = body.global_position
	if moved < STUCK_NUDGE_DIST * delta * 60.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time >= 0.5:
		_stuck_time = 0.0
		# Nudge perpendicular to the current intent to slide off obstacles/walls.
		var perp := Vector3(-desired_dir.z, 0.0, desired_dir.x)
		_knockback += perp * maxf(desired_speed * 0.6, 1.0)
