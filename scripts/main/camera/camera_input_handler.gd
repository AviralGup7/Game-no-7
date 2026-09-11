class_name CameraInputHandler
extends RefCounted

## Gathers manual orbit input from keyboard actions, the InputMap-bound right
## stick, mouse motion, and touch look-deltas. Returns this-frame yaw/pitch
## *degrees* so the orbit controller does not have to guess units.
##
## The InputMap already binds `camera_look_*` to JOY_AXIS_RIGHT_*; reading the
## raw stick on top of `Input.get_axis` doubled gamepad orbit speed. Touch used
## to synthesize a MouseMotion without a pressed button, which this handler
## ignored — right-half drag therefore did nothing on a phone.

var _mouse_accum := Vector2.ZERO
var _touch_accum := Vector2.ZERO
var _profile: CameraProfile = null


func setup(profile: CameraProfile) -> void:
	_profile = profile


func set_profile(profile: CameraProfile) -> void:
	_profile = profile


func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if event == null:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		handle_look_delta(event.relative)
	elif DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
		handle_look_delta(event.relative)


## Mouse (and any other pixel-delta look source). Finite-only: a NaN relative
## would latch the orbit yaw for the rest of the run.
func handle_look_delta(relative: Vector2) -> void:
	if not is_finite(relative.x) or not is_finite(relative.y):
		return
	_mouse_accum += relative


## Finger look in degrees, sized to the viewport so a swipe is the same turn on
## a 720p window and a 1080p phone. Does not go through mouse_orbit_sensitivity.
func handle_touch_look(relative: Vector2, viewport_size: Vector2) -> void:
	if _profile == null:
		return
	if not is_finite(relative.x) or not is_finite(relative.y):
		return
	var width := viewport_size.x
	var height := viewport_size.y
	if not is_finite(width) or width < 1.0:
		width = 1280.0
	if not is_finite(height) or height < 1.0:
		height = 720.0
	_touch_accum.x += (relative.x / width) * _profile.touch_orbit_yaw_per_screen
	_touch_accum.y += (relative.y / height) * _profile.touch_orbit_pitch_per_screen


func gather(delta: float) -> Vector2:
	if _profile == null:
		return Vector2.ZERO
	if not is_finite(delta) or delta <= 0.0:
		_mouse_accum = Vector2.ZERO
		_touch_accum = Vector2.ZERO
		return Vector2.ZERO

	var analog_yaw := 0.0
	var analog_pitch := 0.0

	# Actions already include the gamepad right stick via project.godot. Do not
	# also read JOY_AXIS_RIGHT_* — that doubled analog orbit.
	if InputMap.has_action("camera_look_left") and InputMap.has_action("camera_look_right"):
		analog_yaw += Input.get_axis("camera_look_left", "camera_look_right")
	if InputMap.has_action("camera_look_up") and InputMap.has_action("camera_look_down"):
		analog_pitch += Input.get_axis("camera_look_up", "camera_look_down")

	var dead := _profile.orbit_input_deadzone
	if absf(analog_yaw) < dead:
		analog_yaw = 0.0
	if absf(analog_pitch) < dead:
		analog_pitch = 0.0

	var yaw_deg := analog_yaw * _profile.orbit_speed_deg * delta
	var pitch_deg := analog_pitch * _profile.orbit_speed_deg * delta

	# Mouse/touch: consume the whole accum this frame (no leftover lerp that
	# kept re-triggering the auto-follow cooldown after the finger lifted).
	if _mouse_accum.length_squared() > 0.0001:
		yaw_deg += _mouse_accum.x * _profile.mouse_orbit_sensitivity
		pitch_deg += _mouse_accum.y * _profile.mouse_orbit_sensitivity
		_mouse_accum = Vector2.ZERO

	if not is_finite(yaw_deg) or not is_finite(pitch_deg):
		return Vector2.ZERO
	return Vector2(yaw_deg, pitch_deg)


func reset() -> void:
	_mouse_accum = Vector2.ZERO
