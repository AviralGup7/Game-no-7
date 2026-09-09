extends RefCounted

## Regression for "the run dies a few steps after I move the joystick".
##
## A single non-finite (NaN/inf) value on the locomotion path is self-perpetuating: it
## is integrated into a CharacterBody3D and lerped into the camera rig, where it stays
## non-finite for every later frame, and the physics/renderer abort some time after the
## bad frame — which is why the failure looks delayed instead of immediate. These cases
## pin the boundary guarantees: a bad sample is refused at every hand-off, and a value
## that is already poisoned never escapes a component.
##
## Deliberately tree- and physics-free: only the pure surfaces are driven, so a case
## cannot destabilise the headless run that is supposed to be protecting it.


static func suite() -> Array:
	var results: Array = []
	_joystick(results)
	_locomotion(results)
	_controller(results)
	_camera_math(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _finite2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


static func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


# --- VirtualJoystick: the source of the analog value ------------------------

static func _joystick(results: Array) -> void:
	# A degenerate radius used to divide the drag offset straight into inf/NaN, and the
	# player latched that value for the rest of the run (the stick only re-sends on
	# change), so the hero kept "pushing" into garbage until the physics blew up.
	var stick := VirtualJoystick.new()
	stick.radius = 0.0
	stick._begin(0, Vector2(20, 20))
	stick._update(Vector2(140, 20))
	var v := stick.get_value()
	_check(results, "zero radius cannot produce a non-finite stick value", _finite2(v),
		"got %s" % str(v))
	_check(results, "zero radius keeps the value inside the unit circle", v.length() <= 1.0001,
		"length %.4f" % v.length())
	stick.free()

	# A non-finite pointer position is dropped, leaving the stick at rest.
	var fresh := VirtualJoystick.new()
	fresh._begin(0, Vector2(20, 20))
	fresh._update(Vector2(INF, -INF))
	_check(results, "infinite drag position is ignored", fresh.get_value() == Vector2.ZERO,
		"got %s" % str(fresh.get_value()))
	fresh._update(Vector2(NAN, 20))
	_check(results, "NaN drag position is ignored", fresh.get_value() == Vector2.ZERO,
		"got %s" % str(fresh.get_value()))
	# A valid drag still works after bad samples were refused (radius default 96).
	fresh._update(Vector2(20.0 + 96.0, 20.0))
	_check(results, "valid drag after bad samples still deflects", _finite2(fresh.get_value())
		and fresh.get_value().length() > 0.9, "got %s" % str(fresh.get_value()))
	fresh._end()
	_check(results, "release returns to neutral", fresh.get_value() == Vector2.ZERO)
	fresh.free()

	# A non-finite press must not capture at all: there is no base to measure from.
	var no_start := VirtualJoystick.new()
	no_start._begin(0, Vector2(NAN, 4.0))
	_check(results, "non-finite press does not capture", not no_start.is_active())
	no_start._update(Vector2(50, 50))
	no_start._update(Vector2(50, 50))
	_check(results, "un-captured stick reports no motion", no_start.get_value() == Vector2.ZERO,
		"got %s" % str(no_start.get_value()))
	no_start.free()

	# Mouse parity: the stick has to be draggable in the editor so this exact path is
	# reproducible without a touch device (press -> drag -> release).
	var mouse_stick := VirtualJoystick.new()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(30, 20)
	mouse_stick._gui_input(press)
	_check(results, "mouse press captures the stick", mouse_stick.is_active())
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(130, 20)
	mouse_stick._gui_input(drag)
	_check(results, "mouse drag produces a full deflection",
		_finite2(mouse_stick.get_value()) and absf(mouse_stick.get_value().x - 1.0) < 0.01,
		"got %s" % str(mouse_stick.get_value()))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	mouse_stick._gui_input(release)
	_check(results, "mouse release returns to neutral",
		not mouse_stick.is_active() and mouse_stick.get_value() == Vector2.ZERO)
	mouse_stick.free()


# --- PlayerLocomotion: the UI -> gameplay hand-off --------------------------

static func _locomotion(results: Array) -> void:
	var loco := PlayerLocomotion.new()
	loco.set_move_input(Vector2(NAN, 3.0))
	_check(results, "NaN stick sample is zeroed, not latched", loco.current_input() == Vector2.ZERO,
		"got %s" % str(loco.current_input()))
	loco.set_move_input(Vector2(INF, -INF))
	_check(results, "infinite stick sample is zeroed", loco.current_input() == Vector2.ZERO,
		"got %s" % str(loco.current_input()))
	_check(results, "gather() never hands out a non-finite vector", _finite2(loco.gather()),
		"got %s" % str(loco.gather()))
	loco.set_move_input(Vector2(0.6, 0.8))
	_check(results, "valid analog input is kept", loco.current_input() == Vector2(0.6, 0.8),
		"got %s" % str(loco.current_input()))
	loco.set_move_input(Vector2(3.0, 4.0))
	_check(results, "over-long input is normalised",
		absf(loco.current_input().length() - 1.0) < 0.001,
		"length %.4f" % loco.current_input().length())
	loco.set_move_input(Vector2(0.6, 0.8))
	loco.clear()
	_check(results, "clear() zeroes intent", loco.current_input() == Vector2.ZERO)

	# Headless fixture shape: bound to nothing (no body, controller or dodge). The
	# bounds path must still be a safe no-op instead of dereferencing a null body.
	loco.clear_and_idle()
	loco.set_bounds(12.0)
	loco.clamp_to_bounds()
	_check(results, "unbound locomotion tolerates bounds + idle with no body",
		loco.current_input() == Vector2.ZERO)

	# A zeroed bad sample must not create a move edge (it drives HUD + coach state).
	var edges := [0, 0]
	loco.move_started.connect(func() -> void: edges[0] += 1)
	loco.move_stopped.connect(func() -> void: edges[1] += 1)
	loco.set_move_input(Vector2(NAN, NAN))
	loco.track(loco.current_input())
	_check(results, "zeroed bad sample emits no move edge", edges[0] == 0 and edges[1] == 0,
		"started %d, stopped %d" % [edges[0], edges[1]])


# --- CharacterController: the gameplay -> physics hand-off ------------------

static func _controller(results: Array) -> void:
	var cc := CharacterController.new()
	# Unbound (no owner body) must be a no-op rather than an error: the harness and
	# fixtures build controllers before a scene wires them.
	cc.tick(Vector2(1.0, 0.0), 1.0 / 60.0)
	cc.tick(Vector2(NAN, NAN), 1.0 / 60.0)
	cc.apply_dash(Vector3(NAN, 0.0, 0.0), 12.0, 1.0 / 60.0)
	cc.apply_dash(Vector3(1.0, 0.0, 0.0), INF, 1.0 / 60.0)
	cc.face_direction(Vector3(INF, 0.0, INF))
	cc.stop()
	_check(results, "unbound controller does not fault on poisoned inputs (smoke)", true)

	_check(results, "movement math flags non-finite vectors",
		not cc._is_finite_v2(Vector2(1.0, NAN)) and not cc._is_finite_v3(Vector3(0.0, 0.0, INF)))
	var cleaned := cc._clean_velocity(Vector3(NAN, 4.0, INF))
	_check(results, "poisoned velocity is repaired component-wise", cleaned == Vector3(0.0, 4.0, 0.0),
		"got %s" % str(cleaned))
	_check(results, "sanitize drops non-finite input", cc._sanitize(Vector2(INF, 0.5)) == Vector2.ZERO)
	_check(results, "sanitize keeps valid analog magnitude",
		absf(cc._sanitize(Vector2(0.3, 0.4)).length() - 0.5) < 0.001)

	# A zero delta used to make every acceleration term inf; NaN/inf/-delta are just as
	# bad. None of them may register movement intent.
	var bad_deltas: Array[float] = [NAN, INF, 0.0, -1.0]
	for bad_delta in bad_deltas:
		cc.tick(Vector2(1.0, 0.0), bad_delta)
	_check(results, "bad delta never registers movement intent", not cc.is_moving(),
		"last input %s" % str(cc.get_debug_snapshot()["move_input"]))

	# The camera-relative basis must collapse to "no motion", never NaN, whatever the
	# camera transform or input looks like.
	_check(results, "world direction stays finite for any input",
		_finite3(cc.screen_to_world_dir(Vector2(0.5, 0.5)))
		and _finite3(cc.screen_to_world_dir(Vector2(NAN, NAN)))
		and cc.screen_to_world_dir(Vector2(NAN, NAN)) == Vector3.ZERO,
		"got %s" % str(cc.screen_to_world_dir(Vector2(NAN, NAN))))

	# Progression/save-driven speed setters must stay inside a sane finite range:
	# `maxf(value, 0.0)` let inf through, which overflows the whole velocity.
	cc.set_move_speed(INF)
	_check(results, "infinite move speed is clamped to the ceiling", cc.move_speed <= 40.0,
		"got %.2f" % cc.move_speed)
	cc.set_move_speed(NAN)
	_check(results, "NaN move speed becomes 0, not NaN", is_equal_approx(cc.move_speed, 0.0),
		"got %.4f" % cc.move_speed)
	cc.set_move_speed(-3.0)
	_check(results, "negative move speed clamps to 0", is_equal_approx(cc.move_speed, 0.0),
		"got %.4f" % cc.move_speed)
	cc.set_move_speed(6.0)
	_check(results, "valid move speed passes through", is_equal_approx(cc.move_speed, 6.0),
		"got %.4f" % cc.move_speed)
	var snap: Dictionary = cc.get_debug_snapshot()
	_check(results, "controller snapshot stays finite",
		snap.has("move_speed") and is_finite(float(snap["move_speed"])),
		"got %s" % str(snap))


# --- CameraMath: the shared finiteness gate ---------------------------------

static func _camera_math(results: Array) -> void:
	_check(results, "CameraMath flags non-finite vectors",
		not CameraMath.is_finite_v3(Vector3(0.0, NAN, 0.0))
		and CameraMath.is_finite_v3(Vector3(1.0, 2.0, 3.0)))
	var good := Transform3D(Basis(), Vector3(1.0, 2.0, 3.0))
	_check(results, "CameraMath accepts a clean transform", CameraMath.is_finite_transform(good))
	var bad := Transform3D(Basis(Vector3(1.0, NAN, 0.0), Vector3.UP, Vector3.FORWARD), Vector3.ZERO)
	_check(results, "CameraMath rejects a NaN basis axis", not CameraMath.is_finite_transform(bad))
	_check(results, "CameraMath rejects a NaN origin",
		not CameraMath.is_finite_transform(Transform3D(Basis(), Vector3(0.0, 0.0, INF))))
	_check(results, "yaw from a zero direction is defined",
		is_finite(CameraMath.yaw_from_direction(Vector3.ZERO)))
	_check(results, "infinite distance is rejected, not laundered",
		not _finite3(CameraMath.spherical_offset(0.0, 0.0, INF)))
	_check(results, "finite distance stays finite",
		_finite3(CameraMath.spherical_offset(0.0, 0.0, 4.0)))
