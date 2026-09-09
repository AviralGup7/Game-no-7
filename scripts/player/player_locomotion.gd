class_name PlayerLocomotion
extends RefCounted

## Player locomotion input + bounds, extracted from Player. Gathers the movement
## vector (virtual joystick, falling back to keyboard/controller actions), clamps
## the body inside the arena interior, and tracks move start/stop transitions.
## Player re-emits the move signals so its public signal contract is unchanged.
##
## Typed refs: `dodge` is nullable (headless fixtures bind without one), the
## controller is the concrete CharacterController type.

signal move_started
signal move_stopped

var _body: CharacterBody3D = null
var _dodge: DodgeController = null
var _controller: CharacterController = null
var _move_input := Vector2.ZERO
var _using_actions := true
var _bounds_half := -1.0   # -1 => no clamp (set by the scene owner / main)
var _was_moving := false


func bind(body: CharacterBody3D, dodge: DodgeController, controller: CharacterController) -> void:
	_body = body
	_dodge = dodge
	_controller = controller
	if _dodge != null:
		_dodge.set_bounds(_bounds_half)


func set_using_actions(enabled: bool) -> void:
	_using_actions = enabled


func uses_actions() -> bool:
	return _using_actions


func set_move_input(input_vector: Vector2) -> void:
	_move_input = input_vector
	if _move_input.length_squared() > 1.0:
		_move_input = _move_input.normalized()


func current_input() -> Vector2:
	return _move_input


func clear() -> void:
	_move_input = Vector2.ZERO
	track(Vector2.ZERO)


## Full stop: clear intent and settle the controller in place.
func clear_and_idle() -> void:
	clear()
	if _controller != null:
		_controller.stop()
	elif _body != null:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0


## Set the arena interior half-extent for movement/bounds clamping; -1 disables it.
func set_bounds(half: float) -> void:
	_bounds_half = half
	if _dodge != null:
		_dodge.set_bounds(half)


func gather() -> Vector2:
	var v := _move_input
	if _using_actions and _move_input == Vector2.ZERO:
		var x := Input.get_axis("move_left", "move_right")
		var y := Input.get_axis("move_up", "move_down")
		v = Vector2(x, y)
		if v.length_squared() > 1.0:
			v = v.normalized()
	return v


func track(move: Vector2) -> void:
	if _was_moving and move == Vector2.ZERO:
		move_stopped.emit()
	elif not _was_moving and move != Vector2.ZERO:
		move_started.emit()
	_was_moving = move != Vector2.ZERO


func clamp_to_bounds() -> void:
	if _bounds_half < 0.0 or _body == null:
		return
	var limit := maxf(_bounds_half - 0.5, 0.0)
	var p := _body.global_position
	var clamped := Vector3(clampf(p.x, -limit, limit), p.y, clampf(p.z, -limit, limit))
	if clamped.x != p.x and _body.velocity.x * p.x > 0.0:
		_body.velocity.x = 0.0
	if clamped.z != p.z and _body.velocity.z * p.z > 0.0:
		_body.velocity.z = 0.0
	if clamped != p:
		_body.global_position = clamped
