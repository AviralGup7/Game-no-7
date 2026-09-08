extends Node3D
class_name CameraRig

## Perfect third-person following camera.
##
## Design reference – studied from top online games:
## - Elden Ring / Dark Souls 3: gentle yaw auto-follow behind sustained movement,
##   deadzone ~28°, delay 0.55s, suppress when walking toward camera (dot > threshold),
##   strafe suppression, no fighting when strafing.
## - Zelda BOTW/OOT: spring-arm sphere-cast collision, pitch limits, reset behind player,
##   focus point = player + look_height + predictive velocity.
## - God of War 2018 / TLOU / Uncharted: cinematic framing with shoulder offset,
##   separate smoothing for yaw/pitch/position/distance/FOV, look-ahead based on velocity,
##   FOV boost on sprint, trauma-based shake with noise, never instant snap.
## - GDC Fundamentals (Haigh-Hutchinson): motion & orientation lag for loose feel,
##   preserve control reference frame, minimize reorientation, don't require manual camera
##   to play, interpolate rather than snap.
##
## Architecture:
## - Focus point (player + look_height + velocity * predictive) smoothed with exponential decay.
## - Spherical orbit: yaw, pitch, distance with independent smoothing. Yaw auto-corrects
##   toward movement direction after sustained movement, with deadzone & toward-camera suppression.
## - Manual orbit via right stick / mouse / camera_look actions, with cooldown that suspends auto-follow.
## - Collision: sphere-cast from focus to desired pos (fast pull-in, slow push-out), whiskers for tight spaces,
##   ground clearance guard.
## - Framing: shoulder offset (lateral) applied in camera space, slight look-ahead.
## - FOV: dynamic boost on speed, smoothed.
## - Shake: trauma from HitstopManager (FastNoiseLite) + event-driven shakes, reduced-motion safe.
## - Fully data-driven via CameraProfile.

const CAMERA_GROUP := &"camera_rig"

# Core refs
var _target: Node3D = null
var _profile: CameraProfile = null
var _camera: Camera3D = null
var _enabled := false
var _reduced_motion := false
var _base_cam_local := Vector3.ZERO

# Spherical state
var _current_yaw: float = 0.0
var _target_yaw: float = 0.0
var _current_pitch: float = 0.55 # ~31°
var _target_pitch: float = 0.55
var _current_distance: float = 9.0
var _target_distance: float = 9.0
var _collision_distance: float = 9.0

# Focus
var _focus_point := Vector3.ZERO
var _desired_focus := Vector3.ZERO
var _focus_velocity := Vector3.ZERO

# Velocity tracking
var _last_target_pos := Vector3.ZERO
var _target_velocity := Vector3.ZERO
var _target_speed := 0.0
var _last_move_dir_world := Vector3.ZERO

# Auto follow
var _move_sustain_timer := 0.0
var _manual_cooldown := 0.0
var _auto_follow_active := false

# Manual input accumulation
var _manual_yaw_input := 0.0
var _manual_pitch_input := 0.0
var _mouse_delta_accum := Vector2.ZERO

# Collision
var _collision_recovery_timer := 0.0
var _is_colliding := false

# Shake
var _shake_remaining := 0.0
var _shake_amplitude := 0.0
var _shake_time := 0.0
var _noise := FastNoiseLite.new()
var _current_fov: float = 62.0
var _hitstop_manager: Node = null

# Smoothing helpers
var _has_snapped := false


func _ready() -> void:
	add_to_group(String(CAMERA_GROUP))
	_camera = _find_camera()
	if _camera != null:
		_camera.make_current()
		# Perfect camera: rig owns world position, Camera3D local is zero + shake only.
		# Ignore authored offset (0,4,8) from old scene – we want clean spring-arm.
		_base_cam_local = Vector3.ZERO
		_camera.position = Vector3.ZERO
		_current_fov = _camera.fov
	_noise.seed = 1337
	_noise.frequency = 28.0
	_noise.fractal_octaves = 2

	_profile = ContentRegistry.get_camera_profile(&"default") if ContentRegistry != null else null
	if _profile == null:
		_profile = CameraProfile.new()
	_profile._validated_profile()
	_current_distance = _profile.get_clamped_distance()
	_target_distance = _current_distance
	_collision_distance = _current_distance
	_current_pitch = deg_to_rad(_profile.get_clamped_pitch_deg())
	_target_pitch = _current_pitch
	_current_fov = _profile.field_of_view

	_refresh_settings()
	_wire_combat_feedback()
	_find_hitstop_manager()

	# Ensure we process even if paused? No, camera should pause with game.
	set_process(true)
	set_process_input(true)


func _find_camera() -> Camera3D:
	var found := get_node_or_null("Camera3D") as Camera3D
	if found == null:
		# Fallback: search recursively
		for child in get_children():
			if child is Camera3D:
				return child as Camera3D
			if child is Node:
				var deep := (child as Node).get_node_or_null("Camera3D") as Camera3D
				if deep != null:
					return deep
	return found


func set_target(target: Node3D) -> void:
	_target = target
	_enabled = target != null
	if _enabled and _target != null:
		_last_target_pos = _target.global_position
		_desired_focus = _target.global_position + Vector3(0.0, _profile.look_height, 0.0)
		_focus_point = _desired_focus
		# Initialize yaw behind target facing if possible
		var target_yaw := _get_target_facing_yaw()
		_current_yaw = target_yaw
		_target_yaw = target_yaw
		_apply_follow(1.0, 1.0)
		_has_snapped = true
	else:
		_has_snapped = false


func set_camera_profile(profile: CameraProfile) -> void:
	if profile != null:
		_profile = profile
		_profile._validated_profile()
		_target_distance = _profile.get_clamped_distance()
		_target_pitch = deg_to_rad(_profile.get_clamped_pitch_deg())
		_current_fov = _profile.field_of_view
		_refresh_settings()


func add_shake(amplitude: float, duration: float) -> void:
	if _profile == null:
		return
	if _reduced_motion:
		return
	_shake_amplitude = clampf(amplitude, 0.0, _profile.max_shake_amplitude)
	_shake_remaining = maxf(_shake_remaining, duration)
	# Also push to hitstop trauma if available
	if _hitstop_manager != null and _hitstop_manager.has_method("add_trauma"):
		_hitstop_manager.call("add_trauma", clampf(amplitude * 0.35, 0.0, 1.0))


func reset_transform() -> void:
	_shake_remaining = 0.0
	_shake_amplitude = 0.0
	_manual_cooldown = 0.0
	_move_sustain_timer = 0.0
	_collision_recovery_timer = 0.0
	_mouse_delta_accum = Vector2.ZERO
	if _target != null:
		var yaw := _get_target_facing_yaw()
		_current_yaw = yaw
		_target_yaw = yaw
		_target_pitch = deg_to_rad(_profile.get_clamped_pitch_deg())
		_current_pitch = _target_pitch
		_target_distance = _profile.get_clamped_distance()
		_collision_distance = _target_distance
		_apply_follow(1.0, 1.0)
	if _camera != null:
		_camera.position = _base_cam_local


func reset_orbit() -> void:
	# Public reset behind player (Zelda-style Z-target)
	if _target == null:
		return
	var yaw := _get_target_facing_yaw()
	_target_yaw = yaw
	_target_pitch = deg_to_rad(_profile.get_clamped_pitch_deg())
	_manual_cooldown = 0.0


# ------------------------------------------------------------------
# Input – manual orbit (right stick, mouse, actions)
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Only when mouse captured or right button held, or always for desktop?
		# For arena game, allow mouse orbit when right button held or middle, to avoid fighting.
		# We'll accumulate small amount and treat as manual input if significant.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_mouse_delta_accum += mm.relative
		elif mm.relative.length_squared() > 0.0 and DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
			_mouse_delta_accum += mm.relative
	# Camera reset action (optional)
	if event.is_action_pressed("camera_reset"):
		reset_orbit()


func _gather_manual_input(delta: float) -> Vector2:
	var yaw_input := 0.0
	var pitch_input := 0.0

	# New actions if defined (camera_look_left/right/up/down)
	if InputMap.has_action("camera_look_left") and InputMap.has_action("camera_look_right"):
		yaw_input += Input.get_axis("camera_look_left", "camera_look_right")
	if InputMap.has_action("camera_look_up") and InputMap.has_action("camera_look_down"):
		pitch_input += Input.get_axis("camera_look_up", "camera_look_down")

	# Fallback: right stick JoypadMotion axis 2 (x) and 3 (y) – typical gamepad
	var rs_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var rs_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rs_x) > _profile.orbit_input_deadzone:
		yaw_input += rs_x
	if absf(rs_y) > _profile.orbit_input_deadzone:
		pitch_input += rs_y

	# Mouse accumulated
	if _mouse_delta_accum.length_squared() > 0.01:
		yaw_input += _mouse_delta_accum.x * _profile.mouse_orbit_sensitivity * 0.12
		pitch_input += _mouse_delta_accum.y * _profile.mouse_orbit_sensitivity * 0.12
		_mouse_delta_accum = _mouse_delta_accum.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))

	# Deadzone
	if absf(yaw_input) < _profile.orbit_input_deadzone:
		yaw_input = 0.0
	if absf(pitch_input) < _profile.orbit_input_deadzone:
		pitch_input = 0.0

	return Vector2(yaw_input, pitch_input)


# ------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _enabled or _target == null:
		return
	if not is_instance_valid(_target):
		_enabled = false
		return
	if _profile == null:
		return

	delta = clampf(delta, 0.0, 0.1)
	_test_hitstop_manager()

	# Update velocity tracking
	_update_target_velocity(delta)

	# Manual orbit
	var manual := _gather_manual_input(delta)
	var has_manual := manual.length_squared() > 0.0001

	if has_manual:
		_manual_cooldown = _profile.manual_orbit_cooldown
		_auto_follow_active = false
		_target_yaw -= manual.x * deg_to_rad(_profile.orbit_speed_deg) * delta * 6.0
		_target_pitch += manual.y * deg_to_rad(_profile.orbit_speed_deg) * delta * 6.0
		_target_pitch = clampf(_target_pitch, deg_to_rad(_profile.min_pitch_deg), deg_to_rad(_profile.max_pitch_deg))
	else:
		if _manual_cooldown > 0.0:
			_manual_cooldown = maxf(_manual_cooldown - delta, 0.0)

	# Auto follow (Elden Ring style)
	_update_auto_follow(delta)

	# Smooth yaw/pitch/distance
	_smooth_orbit(delta)

	# Focus point with prediction
	_update_focus_point(delta)

	# Desired camera position from spherical
	var desired_cam_pos := _calculate_desired_position()

	# Collision handling – sphere cast
	var collided_pos := _handle_collision(_focus_point, desired_cam_pos)

	# Apply follow to rig
	var pos_smoothing := _profile.position_smoothing
	if _reduced_motion:
		pos_smoothing = _profile.reduced_motion_smoothing
	var weight := _exp_weight(pos_smoothing, delta)
	if not _has_snapped:
		weight = 1.0
		_has_snapped = true
	global_position = global_position.lerp(collided_pos, weight)

	# Look at focus with framing
	_update_look_at()

	# FOV
	_update_fov(delta)

	# Shake
	_update_shake(delta)


func _apply_follow(weight: float, delta_for_fov: float = 0.016) -> void:
	if _profile == null or _target == null:
		return
	_update_target_velocity(delta_for_fov)
	_update_focus_point(delta_for_fov)
	var desired := _calculate_desired_position()
	var collided := _handle_collision(_focus_point, desired)
	global_position = global_position.lerp(collided, clampf(weight, 0.0, 1.0))
	_update_look_at()
	_update_fov(delta_for_fov)


# ------------------------------------------------------------------
# Velocity & focus
# ------------------------------------------------------------------

func _update_target_velocity(delta: float) -> void:
	if _target == null:
		return
	var curr_pos := _target.global_position
	var diff := curr_pos - _last_target_pos
	# Guard against teleport
	if diff.length_squared() > 100.0:
		_target_velocity = Vector3.ZERO
		_last_target_pos = curr_pos
		return
	var vel := diff / maxf(delta, 0.0001)
	# Smooth velocity
	_target_velocity = _target_velocity.lerp(vel, clampf(delta * 8.0, 0.0, 1.0))
	_target_speed = _target_velocity.length()
	if _target_speed > 0.3:
		_last_move_dir_world = _target_velocity.normalized()
	_last_target_pos = curr_pos


func _update_focus_point(delta: float) -> void:
	if _target == null:
		return
	var base_focus := _target.global_position + Vector3(0.0, _profile.look_height, 0.0)

	# Predictive offset – velocity * factor + look-ahead in move dir
	var predictive := _target_velocity * _profile.predictive_factor
	var look_ahead := Vector3.ZERO
	if _target_speed > 0.5:
		look_ahead = _last_move_dir_world * _profile.look_ahead_distance * clampf(_target_speed / 6.0, 0.0, 1.0)

	_desired_focus = base_focus + predictive + look_ahead

	# Smooth focus – separate vertical lerp for less bobbing when jumping
	var horiz_smoothing := _profile.follow_smoothing
	var vert_smoothing := _profile.focus_height_lerp
	if _reduced_motion:
		horiz_smoothing = _profile.reduced_motion_smoothing
		vert_smoothing = _profile.reduced_motion_smoothing

	var weight_h := _exp_weight(horiz_smoothing, delta)
	var weight_v := _exp_weight(vert_smoothing, delta)

	_focus_point.x = lerpf(_focus_point.x, _desired_focus.x, weight_h)
	_focus_point.z = lerpf(_focus_point.z, _desired_focus.z, weight_h)
	_focus_point.y = lerpf(_focus_point.y, _desired_focus.y, weight_v)

	if _focus_point == Vector3.ZERO:
		_focus_point = _desired_focus


func _get_target_facing_yaw() -> float:
	if _target == null:
		return _current_yaw
	# Use target's basis if available, else keep current
	var basis := _target.global_transform.basis
	var forward := -basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return _current_yaw
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


# ------------------------------------------------------------------
# Auto follow – Elden Ring / Souls inspired
# ------------------------------------------------------------------

func _update_auto_follow(delta: float) -> void:
	if _profile == null or not _profile.auto_follow_enabled:
		_auto_follow_active = false
		return
	if _manual_cooldown > 0.0:
		# Manual orbit suppresses auto follow
		_move_sustain_timer = 0.0
		return
	if _target_speed < 0.6:
		_move_sustain_timer = maxf(_move_sustain_timer - delta * 1.5, 0.0)
		_auto_follow_active = false
		return

	# Sustained movement timer
	_move_sustain_timer += delta

	if _move_sustain_timer < _profile.auto_follow_delay:
		return

	# Movement direction yaw
	var move_dir := _last_move_dir_world
	move_dir.y = 0.0
	if move_dir.length_squared() < 0.0001:
		return
	move_dir = move_dir.normalized()
	var move_yaw := atan2(-move_dir.x, -move_dir.z)

	# Angle difference between current camera yaw and movement yaw
	var diff := _angle_difference(_current_yaw, move_yaw)
	if absf(diff) < deg_to_rad(_profile.auto_follow_deadzone_deg):
		return

	# Toward-camera suppression – if moving toward camera, don't auto follow (Dark Souls behavior)
	# to_cam = from player to camera
	var to_cam := global_position - _focus_point
	to_cam.y = 0.0
	if to_cam.length_squared() > 0.0001:
		to_cam = to_cam.normalized()
		var dot := move_dir.dot(to_cam)
		# dot > 0 => moving toward camera
		if dot > -_profile.auto_follow_toward_camera_threshold:
			# If moving significantly toward camera, suppress
			if dot > 0.25:
				return
			# Strafe suppression: reduce speed when perpendicular
			if absf(dot) < 0.35:
				# Scale speed down
				var suppression := _profile.auto_follow_strafe_suppression
				_target_yaw = _lerp_angle(_target_yaw, move_yaw, clampf(delta * _profile.auto_follow_speed * suppression, 0.0, 1.0))
				_auto_follow_active = true
				return

	# Normal auto follow
	var follow_speed := _profile.auto_follow_speed
	# Scale speed by angle diff (larger diff = faster correction, but capped)
	var speed_scale := clampf(absf(diff) / deg_to_rad(90.0), 0.3, 1.5)
	_target_yaw = _lerp_angle(_target_yaw, move_yaw, clampf(delta * follow_speed * speed_scale, 0.0, 1.0))
	_auto_follow_active = true


func _smooth_orbit(delta: float) -> void:
	var yaw_smooth := _profile.yaw_smoothing
	var pitch_smooth := _profile.pitch_smoothing
	if _reduced_motion:
		yaw_smooth = _profile.reduced_motion_smoothing
		pitch_smooth = _profile.reduced_motion_smoothing

	var yaw_weight := _exp_weight(yaw_smooth, delta)
	var pitch_weight := _exp_weight(pitch_smooth, delta)

	_current_yaw = _lerp_angle(_current_yaw, _target_yaw, yaw_weight)
	_current_pitch = lerpf(_current_pitch, _target_pitch, pitch_weight)

	# Distance smoothing with different in/out speeds
	var dist_target := _target_distance
	# If colliding, target is collision distance
	if _is_colliding:
		dist_target = _collision_distance

	var dist_smooth := _profile.distance_smoothing_out
	if dist_target < _current_distance:
		dist_smooth = _profile.distance_smoothing_in
	if _reduced_motion:
		dist_smooth = _profile.reduced_motion_smoothing

	var dist_weight := _exp_weight(dist_smooth, delta)
	_current_distance = lerpf(_current_distance, dist_target, dist_weight)
	_current_distance = clampf(_current_distance, _profile.min_distance, _profile.max_distance)


# ------------------------------------------------------------------
# Position & collision
# ------------------------------------------------------------------

func _calculate_desired_position() -> Vector3:
	# Spherical offset + base height + shoulder
	var pitch := _current_pitch
	var yaw := _current_yaw
	var dist := _current_distance

	var horiz := dist * cos(pitch)
	var vert := dist * sin(pitch)

	var offset := Vector3(
		sin(yaw) * horiz,
		vert + _profile.height * 0.55,
		cos(yaw) * horiz
	)

	# Shoulder offset – lateral in camera space
	# Compute right vector from yaw
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	offset += right * _profile.shoulder_offset.x
	offset.y += _profile.shoulder_offset.y

	return _focus_point + offset


func _handle_collision(from: Vector3, to: Vector3) -> Vector3:
	if _profile == null:
		return to

	var dir := to - from
	var dist := dir.length()
	if dist < 0.001:
		return to

	# Sphere cast
	var hit := _sphere_cast(from, to, _profile.collision_radius)
	var target_dist := dist

	if hit.has("fraction"):
		var safe := float(hit.get("fraction", 1.0))
		# Pull in with margin
		target_dist = maxf(dist * safe - 0.25, _profile.min_distance)
		_is_colliding = true
		_collision_recovery_timer = _profile.collision_recovery_delay
	else:
		# No hit – check whiskers for tight spaces (predictive)
		var whisker_dist := _whisker_check(from, to)
		if whisker_dist < dist:
			target_dist = whisker_dist
			_is_colliding = true
			_collision_recovery_timer = _profile.collision_recovery_delay
		else:
			if _collision_recovery_timer > 0.0:
				_collision_recovery_timer -= get_process_delta_time()
				_is_colliding = true
			else:
				_is_colliding = false

	_collision_distance = clampf(target_dist, _profile.min_distance, _profile.max_distance)

	# If colliding, return point along dir at collision distance, else full to
	if _is_colliding:
		var final_dir := dir.normalized()
		var result := from + final_dir * _collision_distance
		# Ground clearance
		result = _enforce_ground_clearance(result, from)
		return result
	else:
		var result := from + dir.normalized() * _current_distance
		# Still enforce ground clearance
		result = _enforce_ground_clearance(result, from)
		return result


func _sphere_cast(from: Vector3, to: Vector3, radius: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}

	# Try shape cast_motion first (Godot 4)
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.05)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(BASIS, from)
	query.motion = to - from
	query.collision_mask = 1 # WorldStatic
	query.margin = 0.02
	if _target != null and _target is CollisionObject3D:
		query.exclude = [_target.get_rid()]

	# cast_motion returns [safe_fraction, unsafe_fraction]
	var result := space.cast_motion(query)
	if result.size() >= 2:
		var safe := float(result[0])
		var unsafe := float(result[1])
		if safe < 1.0 - 0.001:
			var point := from + (to - from) * safe
			return {"fraction": safe, "unsafe": unsafe, "point": point}

	# Fallback: raycast
	var ray_query := PhysicsRayQueryParameters3D.create(from, to)
	ray_query.collision_mask = 1
	if _target != null and _target is CollisionObject3D:
		ray_query.exclude = [_target.get_rid()]
	var ray_result := space.intersect_ray(ray_query)
	if not ray_result.is_empty():
		var hit_pos: Vector3 = ray_result.get("position", to)
		var hit_dist := from.distance_to(hit_pos)
		var total_dist := from.distance_to(to)
		if total_dist > 0.001:
			return {"fraction": hit_dist / total_dist, "point": hit_pos}
	return {}


func _whisker_check(from: Vector3, to: Vector3) -> float:
	# Cast a few angled rays to detect tight spaces early (camera whiskers)
	if _profile.whisker_count <= 0:
		return from.distance_to(to)
	var space := get_world_3d().direct_space_state
	if space == null:
		return from.distance_to(to)

	var dir := (to - from).normalized()
	var base_dist := from.distance_to(to)
	var min_dist := base_dist

	var yaw := _current_yaw
	for i in range(_profile.whisker_count):
		var angle_offset := deg_to_rad(_profile.whisker_angle_deg) * (i + 1) * (1 if i % 2 == 0 else -1)
		var test_yaw := yaw + angle_offset
		var test_dir := Vector3(sin(test_yaw) * cos(_current_pitch), sin(_current_pitch), cos(test_yaw) * cos(_current_pitch)).normalized()
		var test_to := from + test_dir * base_dist

		var q := PhysicsRayQueryParameters3D.create(from, test_to)
		q.collision_mask = 1
		if _target != null and _target is CollisionObject3D:
			q.exclude = [_target.get_rid()]
		var res := space.intersect_ray(q)
		if not res.is_empty():
			var hit_pos: Vector3 = res.get("position", test_to)
			var d := from.distance_to(hit_pos) - 0.3
			min_dist = minf(min_dist, d)

	return clampf(min_dist, _profile.min_distance, base_dist)


func _enforce_ground_clearance(cam_pos: Vector3, focus: Vector3) -> Vector3:
	# Prevent camera going below ground
	var space := get_world_3d().direct_space_state
	if space == null:
		return cam_pos

	var down_from := cam_pos + Vector3(0.0, 0.5, 0.0)
	var down_to := cam_pos + Vector3(0.0, -6.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(down_from, down_to)
	query.collision_mask = 1
	var result := space.intersect_ray(query)
	if not result.is_empty():
		var ground_y: float = result.get("position", cam_pos).y
		var min_y := ground_y + _profile.ground_clearance
		if cam_pos.y < min_y:
			cam_pos.y = min_y
	# Also prevent camera going too far below focus
	var min_allowed := focus.y - 1.0
	if cam_pos.y < min_allowed:
		cam_pos.y = lerp(cam_pos.y, min_allowed, 0.5)

	return cam_pos


# ------------------------------------------------------------------
# Look at & FOV & Shake
# ------------------------------------------------------------------

func _update_look_at() -> void:
	if _camera == null:
		return
	if _focus_point == Vector3.ZERO:
		return

	var cam_origin := _camera.global_position
	# If camera global is not yet set, use rig pos
	if cam_origin == Vector3.ZERO:
		cam_origin = global_position

	# Look target with slight vertical framing and velocity influence
	var look_target := _focus_point
	look_target += _target_velocity * _profile.velocity_influence * 0.12
	# Slight shoulder vertical offset already in camera pos, but add to look for framing
	look_target.y += _profile.shoulder_offset.y * 0.3

	# Compute look transform preserving origin
	var forward := (look_target - cam_origin).normalized()
	if forward.length_squared() < 0.0001:
		return

	# Use looking_at from origin
	var up := Vector3.UP
	# Avoid gimbal when looking straight up/down
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.FORWARD

	var target_transform := Transform3D(BASIS, cam_origin).looking_at(look_target, up)
	_camera.global_transform = target_transform


func _update_fov(delta: float) -> void:
	if _camera == null or _profile == null:
		return
	var base_fov := _profile.field_of_view
	var target_fov := base_fov

	# Dynamic FOV boost on speed (Uncharted/God of War style)
	if _target_speed > _profile.fov_sprint_threshold:
		var boost := clampf((_target_speed - _profile.fov_sprint_threshold) * _profile.fov_speed_boost * 0.18, 0.0, _profile.fov_max_boost)
		target_fov += boost

	# Smooth
	var weight := _exp_weight(_profile.fov_smoothing, delta)
	if _reduced_motion:
		weight = _exp_weight(_profile.reduced_motion_smoothing, delta)
	_current_fov = lerpf(_current_fov, target_fov, weight)
	_camera.fov = _current_fov


func _update_shake(delta: float) -> void:
	if _camera == null:
		return

	_shake_time += delta
	var trauma_offset := Vector3.ZERO
	var trauma_roll := 0.0

	# HitstopManager trauma (best quality noise)
	if _hitstop_manager != null:
		if _hitstop_manager.has_method("get_shake_offset"):
			trauma_offset += _hitstop_manager.call("get_shake_offset", 0.35)
		if _hitstop_manager.has_method("get_shake_roll"):
			trauma_roll += _hitstop_manager.call("get_shake_roll", 0.025)

	# Own event-driven shake (boss, wave, etc.)
	if _shake_remaining > 0.0:
		_shake_remaining = maxf(_shake_remaining - delta, 0.0)
		var fade := _shake_remaining / maxf(_shake_remaining + 0.12, 0.001)
		fade = clampf(fade, 0.0, 1.0)
		var strength := _shake_amplitude * fade

		# Use noise for smoothness, not pure rand
		var nx := _noise.get_noise_1d(_shake_time * _profile.shake_frequency)
		var ny := _noise.get_noise_1d(_shake_time * _profile.shake_frequency + 100.0)
		var nz := _noise.get_noise_1d(_shake_time * _profile.shake_frequency + 200.0) * 0.35
		var own_offset := Vector3(nx, ny, nz) * strength

		trauma_offset += own_offset
		trauma_roll += _noise.get_noise_1d(_shake_time * _profile.shake_frequency + 300.0) * strength * 0.06

		if _shake_remaining <= 0.001:
			_shake_amplitude = 0.0

	if _reduced_motion:
		trauma_offset = Vector3.ZERO
		trauma_roll = 0.0

	# Apply as local offset + roll
	# Keep base local at zero for clean shake, but preserve original base if any
	_camera.position = _base_cam_local + trauma_offset

	if absf(trauma_roll) > 0.0001:
		# Apply roll around forward axis
		_camera.global_transform = _camera.global_transform.rotated_local(Vector3.FORWARD, trauma_roll)


func _test_hitstop_manager() -> void:
	if _hitstop_manager != null and is_instance_valid(_hitstop_manager):
		return
	var tree := get_tree()
	if tree == null:
		return
	_hitstop_manager = tree.get_first_node_in_group("hitstop_manager")
	if _hitstop_manager == null:
		# Fallback: find by name in WorldRoot
		var world := tree.current_scene as Node
		if world != null:
			_hitstop_manager = world.get_node_or_null("WorldRoot/HitstopManager")
			if _hitstop_manager == null:
				# Search recursively for HitstopManager
				_hitstop_manager = _find_node_by_class(world, "HitstopManager")


func _find_node_by_class(root: Node, cls_name: String) -> Node:
	if root == null:
		return null
	if root.get_class() == cls_name or (root.has_method("get_class") and root.get_class() == cls_name):
		return root
	if root is HitstopManager:
		return root
	for child in root.get_children():
		var found := _find_node_by_class(child as Node, cls_name)
		if found != null:
			return found
	return null


# ------------------------------------------------------------------
# Settings & events
# ------------------------------------------------------------------

func _refresh_settings() -> void:
	_reduced_motion = SaveManager.get_settings().reduced_motion if SaveManager != null and SaveManager.has_method("get_settings") else false
	if _profile != null:
		_noise.frequency = _profile.shake_frequency


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func _wire_combat_feedback() -> void:
	if EventBus == null:
		return
	if not EventBus.skill_cast.is_connected(_on_skill_shake):
		EventBus.skill_cast.connect(_on_skill_shake)
	if not EventBus.enemy_killed.is_connected(_on_kill_shake):
		EventBus.enemy_killed.connect(_on_kill_shake)
	if not EventBus.wave_completed.is_connected(_on_wave_shake):
		EventBus.wave_completed.connect(_on_wave_shake)
	if not EventBus.boss_spawned.is_connected(_on_boss_shake):
		EventBus.boss_spawned.connect(_on_boss_shake)
	if not EventBus.boss_slain.is_connected(_on_boss_slain_shake):
		EventBus.boss_slain.connect(_on_boss_slain_shake)
	if not EventBus.player_died.is_connected(_on_player_death_shake):
		EventBus.player_died.connect(_on_player_death_shake)


func _on_skill_shake(_skill_id: StringName, _caster: Node) -> void:
	add_shake(0.22, 0.18)


func _on_kill_shake(_enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	add_shake(0.10, 0.12)


func _on_wave_shake(_wave: int, _bonus: int) -> void:
	add_shake(0.35, 0.4)


func _on_boss_shake(_boss: Node, _id: StringName) -> void:
	add_shake(0.6, 0.5)


func _on_boss_slain_shake(_boss_id: StringName) -> void:
	add_shake(0.8, 0.6)


func _on_player_death_shake() -> void:
	add_shake(0.9, 0.7)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _exp_weight(smoothing: float, delta: float) -> float:
	# Exponential decay: 1 - exp(-smoothing * delta) – frame-rate independent
	if smoothing <= 0.0:
		return 1.0
	return 1.0 - exp(-smoothing * delta)


func _lerp_angle(from: float, to: float, weight: float) -> float:
	# Use Godot's built-in angle lerp for shortest path
	return lerp_angle(from, to, clampf(weight, 0.0, 1.0))


func _angle_difference(from: float, to: float) -> float:
	# Shortest signed angle difference
	return wrapf(to - from, -PI, PI)


func get_debug_snapshot() -> Dictionary:
	var p: Dictionary = {}
	if _profile != null:
		p = {
			"profile_id": String(_profile.profile_id),
			"distance": _profile.distance,
			"height": _profile.height,
			"current_distance": _current_distance,
			"target_distance": _target_distance,
			"collision_distance": _collision_distance,
			"is_colliding": _is_colliding,
			"yaw_deg": rad_to_deg(_current_yaw),
			"pitch_deg": rad_to_deg(_current_pitch),
			"fov": _current_fov,
			"auto_follow": _auto_follow_active,
			"manual_cooldown": _manual_cooldown,
			"move_sustain": _move_sustain_timer,
		}
	return {
		"enabled": _enabled,
		"has_target": _target != null and is_instance_valid(_target),
		"profile": p,
		"shake_remaining": _shake_remaining,
		"position": global_position,
		"focus": _focus_point,
		"target_velocity": _target_velocity,
		"target_speed": _target_speed,
	}

## Hardened: validate camera rig lerp.
func _validated_lerp_weight(w: float, delta: float) -> float:
	if not is_finite(w) or w < 0.0:
		w = 0.1
	if not is_finite(delta) or delta <= 0.0:
		delta = 0.016
	return clampf(w * delta * 60.0, 0.0, 1.0)
