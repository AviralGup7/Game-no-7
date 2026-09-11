class_name CameraInputHandler
extends RefCounted

## Gathers manual orbit input from multiple sources – keyboard actions,
## gamepad right stick, mouse motion – with deadzone and sensitivity.
## Inspired by God of War / Uncharted: manual orbit suspends auto-follow.

var _mouse_accum := Vector2.ZERO
var _profile: CameraProfile = null

func setup(profile: CameraProfile) -> void:
	_profile = profile

func set_profile(profile: CameraProfile) -> void:
	_profile = profile

func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_mouse_accum += event.relative
	elif DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
		_mouse_accum += event.relative

func gather(delta: float) -> Vector2:
	if _profile == null:
		return Vector2.ZERO

	var yaw_input := 0.0
	var pitch_input := 0.0

	# Actions
	if InputMap.has_action("camera_look_left") and InputMap.has_action("camera_look_right"):
		yaw_input += Input.get_axis("camera_look_left", "camera_look_right")
	if InputMap.has_action("camera_look_up") and InputMap.has_action("camera_look_down"):
		pitch_input += Input.get_axis("camera_look_up", "camera_look_down")

	# Gamepad right stick – axis 2 = X, 3 = Y (Godot 4)
	var rs_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var rs_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rs_x) > _profile.orbit_input_deadzone:
		yaw_input += rs_x
	if absf(rs_y) > _profile.orbit_input_deadzone:
		pitch_input += rs_y

	# Mouse accumulated – scaled by sensitivity
	if _mouse_accum.length_squared() > 0.01:
		yaw_input += _mouse_accum.x * _profile.mouse_orbit_sensitivity * 0.12
		pitch_input += _mouse_accum.y * _profile.mouse_orbit_sensitivity * 0.12
		_mouse_accum = _mouse_accum.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))

	# Deadzone final
	if absf(yaw_input) < _profile.orbit_input_deadzone:
		yaw_input = 0.0
	if absf(pitch_input) < _profile.orbit_input_deadzone:
		pitch_input = 0.0

	return Vector2(yaw_input, pitch_input)

func reset() -> void:
	_mouse_accum = Vector2.ZERO


## Screen drag already passed GUI capture; do not require a mouse button on Android.
func handle_touch_drag(relative: Vector2) -> void:
	if relative.is_finite():
		_mouse_accum += relative * 0.8
