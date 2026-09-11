extends RefCounted

## Headless unit tests for the camera modules. No World3D, no Camera3D, no tree.
## Pins the defects that made the rig fight the player: double combat boom,
## toward-camera follow, lock-on restore, combat-framing lerp, orbit pitch clamp.


static func suite() -> Array:
	var results: Array = []
	_math(results)
	_auto_follow(results)
	_framing(results)
	_mode(results)
	_orbit_state(results)
	_velocity(results)
	_input(results)
	_fov(results)
	_profile_clamp(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _math(results: Array) -> void:
	_check(results, "exp_weight(0) is instant", is_equal_approx(CameraMath.exp_weight(0.0, 0.16), 1.0))
	var w := CameraMath.exp_weight(3.2, 1.0 / 60.0)
	_check(results, "exp_weight is in (0,1) at 60 Hz", w > 0.0 and w < 1.0, "got %.4f" % w)
	_check(results, "yaw of -Z is 0", is_equal_approx(CameraMath.yaw_from_direction(Vector3(0, 0, -1)), 0.0))
	var behind := CameraMath.spherical_offset(0.0, 0.0, 4.0)
	_check(results, "yaw 0 sits on +Z", _finite3(behind) and absf(behind.z - 4.0) < 0.001, "got %s" % str(behind))


static func _auto_follow(results: Array) -> void:
	var profile := CameraProfile.new()
	profile.auto_follow_enabled = true
	profile.auto_follow_delay = 0.0
	profile.auto_follow_speed = 2.0
	profile.auto_follow_deadzone_deg = 8.0
	profile.auto_follow_toward_camera_threshold = 0.25
	profile.manual_orbit_cooldown = 1.5
	profile._clamp_profile_fields()

	var auto := CameraAutoFollowController.new()
	auto.setup(profile)
	var vel := CameraVelocityTracker.new()
	vel.speed = 5.0
	vel.move_dir = Vector3(0, 0, 1)  # toward +Z = toward a yaw-0 camera
	var orbit := CameraOrbitState.new()
	orbit.current_yaw = 0.0
	orbit.target_yaw = 0.0
	auto.sustain_timer = 1.0
	auto.tick(0.1, vel, orbit, Vector3(0, 2, 8), Vector3.ZERO)
	_check(results, "toward-camera heading suppresses auto-follow", not auto.is_active)
	_check(results, "toward-camera does not yaw the orbit", is_equal_approx(orbit.target_yaw, 0.0),
		"got %.4f" % orbit.target_yaw)

	# Walking away from a camera that is 57° off: follow should pull yaw toward 0.
	vel.move_dir = Vector3(0, 0, -1)
	orbit.current_yaw = 1.0
	orbit.target_yaw = 1.0
	auto.sustain_timer = 1.0
	auto.tick(0.1, vel, orbit, Vector3(0, 2, 8), Vector3.ZERO)
	_check(results, "away-from-camera heading follows", auto.is_active)
	_check(results, "follow yaws toward move heading", absf(orbit.target_yaw) < 1.0,
		"got %.4f" % orbit.target_yaw)

	auto.notify_manual_input()
	_check(results, "manual input arms the cooldown", auto.manual_cooldown > 0.0)
	orbit.target_yaw = 0.8
	auto.tick(0.05, vel, orbit, Vector3(0, 2, 8), Vector3.ZERO)
	_check(results, "cooldown suppresses follow", not auto.is_active)
	_check(results, "cooldown leaves target yaw alone", is_equal_approx(orbit.target_yaw, 0.8),
		"got %.4f" % orbit.target_yaw)


static func _framing(results: Array) -> void:
	var profile := CameraProfile.new()
	profile.combat_framing_enabled = true
	profile.combat_distance_boost_6 = 2.5
	profile.combat_fov_boost_6 = 4.0
	profile.combat_check_interval = 0.25
	profile._clamp_profile_fields()
	var framing := CameraFramingController.new()
	framing.setup(profile)
	var orbit := CameraOrbitState.new()
	orbit.setup_from_profile(profile, 0.0)
	var focus := Vector3(0.0, 1.5, 0.0)
	var a: Vector3 = framing.calculate_desired_position(focus, orbit)
	framing._combat_distance_boost = 5.0
	var b: Vector3 = framing.calculate_desired_position(focus, orbit)
	_check(results, "desired position does not double-apply combat boom", a.is_equal_approx(b),
		"a=%s b=%s" % [str(a), str(b)])

	framing._enemy_count_near = 6
	framing._combat_distance_boost = 0.0
	# 20 frames at 16 ms, never crossing a tree-backed recount.
	for _i in 20:
		framing.tick_combat_framing(0.016, Vector3.ZERO, null)
	_check(results, "combat boom lerps on every frame, not only the 0.25s poll",
		framing.get_combat_distance_boost() > 0.4,
		"got %.4f" % framing.get_combat_distance_boost())


static func _mode(results: Array) -> void:
	var m := CameraModeController.new()
	m.set_mode(CameraModeController.Mode.BOSS, 0.0)
	_check(results, "boss mode sticks", m.current_mode == CameraModeController.Mode.BOSS)
	var dummy := Node3D.new()
	m.set_lock_target(dummy)
	_check(results, "lock target engages lock", m.is_locked())
	_check(results, "lock switches current mode to LOCKED", m.current_mode == CameraModeController.Mode.LOCKED)
	m.set_lock_target(null)
	_check(results, "unlock restores boss, not explore",
		m.current_mode == CameraModeController.Mode.BOSS and not m.is_locked(),
		"mode=%s" % str(m.current_mode))
	dummy.free()

	# Blend actually moves the multiplier off 1.0 instead of snapping.
	var blended := CameraModeController.new()
	var profile := CameraProfile.new()
	profile.combat_distance_multiplier = 1.2
	profile.mode_blend_duration_combat = 1.0
	blended.setup(profile)
	blended.set_mode(CameraModeController.Mode.COMBAT, 1.0)
	blended.tick(0.25)
	var mid := blended.get_mode_distance_multiplier()
	_check(results, "mode distance multiplier blends instead of snapping",
		mid > 1.0 and mid < 1.2, "got %.4f" % mid)


static func _orbit_state(results: Array) -> void:
	var profile := CameraProfile.new()
	profile.distance = 9.0
	profile.pitch_degrees = 32.0
	profile._clamp_profile_fields()
	var state := CameraOrbitState.new()
	state.setup_from_profile(profile, 0.4)
	state.current_distance = 3.0
	state.snap_to_facing(1.2, profile)
	_check(results, "snap_to_facing writes current_distance too",
		is_equal_approx(state.current_distance, profile.get_clamped_distance()),
		"got %.3f" % state.current_distance)
	_check(results, "snap_to_facing writes yaw on both channels",
		is_equal_approx(state.current_yaw, 1.2) and is_equal_approx(state.target_yaw, 1.2))

	var orbit := CameraOrbitController.new()
	var auto := CameraAutoFollowController.new()
	auto.setup(profile)
	orbit.setup(profile, state, null, auto)
	state.target_pitch = 4.0  # ~229°, well past max
	orbit.tick(0.016, CameraVelocityTracker.new(), Vector3(0, 4, 8), Vector3.ZERO, null, null, false)
	var max_rad := deg_to_rad(profile.max_pitch_deg)
	_check(results, "orbit clamps pitch every tick, not only on manual input",
		state.target_pitch <= max_rad + 0.001,
		"got %.3f vs max %.3f" % [state.target_pitch, max_rad])


static func _velocity(results: Array) -> void:
	var vel := CameraVelocityTracker.new()
	vel.setup(Vector3.ZERO, 8.0)
	vel.tick(Vector3(1, 0, 0), 0.05)
	_check(results, "moving sample produces a move_dir", vel.move_dir.length_squared() > 0.0)
	# Slow to a stop: move_dir must not keep the last heading (stale follow).
	for _i in 40:
		vel.tick(Vector3(1, 0, 0), 0.05)
	_check(results, "stationary sample clears move_dir", vel.move_dir == Vector3.ZERO,
		"got %s speed=%.3f" % [str(vel.move_dir), vel.speed])


static func _input(results: Array) -> void:
	var handler := CameraInputHandler.new()
	var profile := CameraProfile.new()
	profile.mouse_orbit_sensitivity = 0.5
	profile.orbit_speed_deg = 90.0
	profile._clamp_profile_fields()
	handler.setup(profile)
	handler.handle_look_delta(Vector2(NAN, 4.0))
	var none := handler.gather(0.016)
	_check(results, "NaN look delta is ignored", none == Vector2.ZERO, "got %s" % str(none))
	handler.handle_look_delta(Vector2(10.0, 0.0))
	var once := handler.gather(0.016)
	_check(results, "look delta is consumed as degrees this frame",
		absf(once.x - 5.0) < 0.001, "got %s" % str(once))
	var twice := handler.gather(0.016)
	_check(results, "look delta does not leak into the next frame",
		twice == Vector2.ZERO, "got %s" % str(twice))

	profile.touch_orbit_yaw_per_screen = 540.0
	profile.touch_orbit_pitch_per_screen = 180.0
	profile._clamp_profile_fields()
	handler.handle_touch_look(Vector2(320.0, 0.0), Vector2(1280.0, 720.0))
	var touch := handler.gather(0.016)
	_check(results, "quarter-width swipe is 135 degrees of yaw",
		absf(touch.x - 135.0) < 0.01, "got %s" % str(touch))
	handler.handle_touch_look(Vector2(NAN, 8.0), Vector2(1280.0, 720.0))
	var nan_touch := handler.gather(0.016)
	_check(results, "NaN touch look is ignored", nan_touch == Vector2.ZERO, "got %s" % str(nan_touch))

	var state := CameraOrbitState.new()
	state.setup_from_profile(profile, 0.0)
	var orbit := CameraOrbitController.new()
	orbit.setup(profile, state, handler, CameraAutoFollowController.new())
	handler.handle_touch_look(Vector2(320.0, 0.0), Vector2(1280.0, 720.0))
	orbit.tick(0.016, CameraVelocityTracker.new(), Vector3(0, 4, 8), Vector3.ZERO, null, null, false)
	var want_yaw := -deg_to_rad(135.0)
	_check(results, "manual look writes current_yaw the same frame",
		absf(state.current_yaw - want_yaw) < 0.02,
		"got %.4f want %.4f" % [state.current_yaw, want_yaw])


static func _fov(results: Array) -> void:
	var fov := CameraFovController.new()
	fov.current_fov = 62.0
	_check(results, "FOV bounds a NaN sample to the last good value",
		is_equal_approx(fov._bounded(NAN), 62.0))
	_check(results, "FOV clamps above Godot's ceiling",
		is_equal_approx(fov._bounded(400.0), 179.0))
	fov.snap_to(INF)
	_check(results, "FOV snap of inf becomes 45", is_equal_approx(fov.current_fov, 45.0))


static func _profile_clamp(results: Array) -> void:
	var profile := CameraProfile.new()
	profile.auto_follow_toward_camera_threshold = -0.38
	profile._clamp_profile_fields()
	_check(results, "negative toward-camera threshold becomes the documented 0.25",
		is_equal_approx(profile.auto_follow_toward_camera_threshold, 0.25),
		"got %.3f" % profile.auto_follow_toward_camera_threshold)
