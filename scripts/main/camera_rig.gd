extends Node3D
class_name CameraRig

## Perfect third-person following camera – MODULARIZED & IMPROVED.
##
## Architecture (modular):
## - CameraInputHandler: gathers manual orbit input
## - CameraVelocityTracker: smooth target velocity + move dir
## - CameraFocusTracker: predictive focus point with separate H/V smoothing
## - CameraOrbitState: pure data (current/target yaw/pitch/distance)
## - CameraAutoFollowController: Elden Ring style gentle auto-follow with deadzone & toward-camera suppression
## - CameraOrbitController: manual orbit + smoothing, delegates to auto-follow
## - CameraCollisionSolver: sphere-cast + whiskers + ground clearance, fast-in/slow-out
## - CameraFramingController: shoulder offset + look-ahead + combat awareness (pull back when surrounded)
## - CameraFovController: dynamic FOV (speed + combat boost)
## - CameraShakeController: trauma noise + event shakes
## - CameraModeController: explore/combat/boss/locked modes with blending
## - CameraMath: shared helpers (exp_weight, lerp_angle, etc.)
##
## Improvements over previous monolithic version:
## - Each concern isolated, testable, reusable
## - Combat framing: counts nearby enemies (group "enemies") every 0.25s, pulls back distance & boosts FOV when surrounded
## - Lock-on framing: Z-target style – when TargetingComponent has best target, camera orbits to keep it in view
## - Mode blending: boss spawn → wider FOV + farther distance, smooth 0.6s blend
## - Teleport guard: if target moves >10m in one frame, snap focus & rig instantly (no long glide)
## - Vertical damping: Y follows with separate slower lerp (focus_height_lerp) to reduce bobbing on jumps
## - Better input: touch drag support placeholder, mouse captured vs right-button, gamepad deadzone
## - Debug snapshot includes all sub-modules
##
## Design reference – same as before (Elden Ring, Zelda BOTW, God of War 2018, Uncharted/TLOU, GDC Fundamentals)

const CAMERA_GROUP := &"camera_rig"

# Core
var _target: Node3D = null
var _profile: CameraProfile = null
var _camera: Camera3D = null
var _enabled := false
var _reduced_motion := false
var _has_snapped := false
var _non_finite_reported := false

# Modules
var _input := CameraInputHandler.new()
var _velocity := CameraVelocityTracker.new()
var _focus := CameraFocusTracker.new()
var _orbit_state := CameraOrbitState.new()
var _auto_follow := CameraAutoFollowController.new()
var _orbit := CameraOrbitController.new()
var _collision := CameraCollisionSolver.new()
var _framing := CameraFramingController.new()
var _fov := CameraFovController.new()
var _shake := CameraShakeController.new()
var _mode := CameraModeController.new()

var _hitstop_manager: Node = null


func _ready() -> void:
	add_to_group(String(CAMERA_GROUP))
	_camera = _find_camera()
	if _camera != null:
		_camera.make_current()
		_camera.position = Vector3.ZERO

	_profile = ContentRegistry.get_camera_profile(&"default") if ContentRegistry != null else null
	if _profile == null:
		_profile = CameraProfile.new()
	_profile._clamp_profile_fields()

	# Setup modules
	_input.setup(_profile)
	_velocity.setup(Vector3.ZERO, 8.0)
	_orbit_state.setup_from_profile(_profile, 0.0)
	_auto_follow.setup(_profile)
	_orbit.setup(_profile, _orbit_state, _input, _auto_follow)
	_collision.setup(_profile)
	_framing.setup(_profile)
	_fov.setup(_profile)
	_shake.setup(_profile, _camera)
	_mode.setup(_profile)

	_refresh_settings()
	_wire_combat_feedback()
	_test_hitstop_manager()

	set_process(true)
	set_process_input(true)


func _find_camera() -> Camera3D:
	var found := get_node_or_null("Camera3D") as Camera3D
	if found == null:
		for child in get_children():
			if child is Camera3D:
				return child as Camera3D
			if child is Node:
				var deep := (child as Node).get_node_or_null("Camera3D") as Camera3D
				if deep != null:
					return deep
	return found


# ------------------------------------------------------------------
# Public API – preserved for backward compat
# ------------------------------------------------------------------

func set_target(target: Node3D) -> void:
	_target = target
	_enabled = target != null
	if _enabled and _target != null:
		_velocity.setup(_target.global_position, 8.0)
		var facing_yaw := _get_target_facing_yaw()
		_orbit_state.setup_from_profile(_profile, facing_yaw)
		var initial_focus := _target.global_position + Vector3(0.0, _profile.look_height, 0.0)
		_focus.setup(_profile, _velocity, initial_focus)
		_apply_follow(1.0, 1.0)
		_has_snapped = true
	else:
		_has_snapped = false


func set_camera_profile(profile: CameraProfile) -> void:
	if profile == null:
		return
	_profile = profile
	_profile._clamp_profile_fields()
	_input.set_profile(_profile)
	_focus.set_profile(_profile)
	_auto_follow.set_profile(_profile)
	_orbit.set_profile(_profile)
	_collision.set_profile(_profile)
	_framing.set_profile(_profile)
	_fov.set_profile(_profile)
	_shake.set_profile(_profile)
	_mode.set_profile(_profile)
	_orbit_state.target_distance = _profile.get_clamped_distance()
	_orbit_state.target_pitch = deg_to_rad(_profile.get_clamped_pitch_deg())
	_refresh_settings()


func add_shake(amplitude: float, duration: float) -> void:
	if _profile == null or _reduced_motion:
		return
	# Cosmetic camera shake: cap event amplitude by the tuned ceiling so a
	# single hard hit never overpowers the profile's max_shake_amplitude budget.
	var capped := amplitude
	if _profile.max_shake_amplitude > 0.0:
		capped = minf(amplitude, _profile.max_shake_amplitude)
	_shake.add_shake(capped, duration, _reduced_motion)


func reset_transform() -> void:
	_shake.reset()
	_auto_follow.reset()
	_input.reset()
	_collision.recovery_timer = 0.0
	_mode.reset()
	if _target != null:
		var yaw := _get_target_facing_yaw()
		_orbit_state.snap_to_facing(yaw, _profile)
		_orbit.reset_orbit(yaw)
		_focus.snap_to(_target.global_position + Vector3(0.0, _profile.look_height, 0.0))
		_velocity.reset(_target.global_position)
		_apply_follow(1.0, 1.0)
	if _camera != null:
		_camera.position = Vector3.ZERO


func reset_orbit() -> void:
	if _target == null:
		return
	var yaw := _get_target_facing_yaw()
	_orbit.reset_orbit(yaw)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func get_debug_snapshot() -> Dictionary:
	var p: Dictionary = {}
	if _profile != null:
		p = {
			"profile_id": String(_profile.profile_id),
			"distance": _profile.distance,
			"height": _profile.height,
			"current_distance": _orbit_state.current_distance,
			"target_distance": _orbit_state.target_distance,
			"collision_distance": _orbit_state.collision_distance,
			"is_colliding": _collision.is_colliding,
			"yaw_deg": rad_to_deg(_orbit_state.current_yaw),
			"pitch_deg": rad_to_deg(_orbit_state.current_pitch),
			"fov": _fov.current_fov,
			"auto_follow": _auto_follow.is_active,
			"manual_cooldown": _auto_follow.manual_cooldown,
			"move_sustain": _auto_follow.sustain_timer,
			"mode": _mode.current_mode,
			"enemy_count": _framing.get_enemy_count(),
			"combat_boost": _framing.get_combat_distance_boost(),
		}
	return {
		"enabled": _enabled,
		"has_target": _target != null and is_instance_valid(_target),
		"profile": p,
		"shake_remaining": _shake.get_remaining() if _shake != null else 0.0,
		"position": global_position,
		"focus": _focus.focus_point,
		"target_velocity": _velocity.velocity,
		"target_speed": _velocity.speed,
		"modules": {
			"input": _input != null,
			"velocity": _velocity != null,
			"focus": _focus != null,
			"orbit": _orbit_state != null,
			"collision": _collision != null,
			"framing": _framing != null,
			"fov": _fov != null,
			"shake": _shake != null,
			"mode": _mode != null,
		}
	}


# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseMotion:
		_input.handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenDrag:
		# Touch drag on right half of screen = camera orbit (mobile)
		var drag := event as InputEventScreenDrag
		var viewport_size := Vector2.ZERO
		var vp := get_viewport()
		if vp != null:
			viewport_size = vp.get_visible_rect().size
		if viewport_size.x > 0.0 and drag.position.x > viewport_size.x * 0.5:
			# Feed as mouse motion scaled for touch
			var mm := InputEventMouseMotion.new()
			mm.relative = drag.relative * 0.8
			_input.handle_mouse_motion(mm)
	if event.is_action_pressed("camera_reset"):
		reset_orbit()


# ------------------------------------------------------------------
# Main loop – modular coordinator
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if not _enabled or _target == null:
		return
	if not is_instance_valid(_target):
		_enabled = false
		return
	if _profile == null:
		return

	delta = clampf(delta, 0.0, 0.1)
	_test_hitstop_manager()
	_mode.tick(delta)
	_collision.tick_recovery(delta)

	# 1. Velocity
	var curr_pos := _target.global_position
	# Teleport guard – snap if >10m
	if _velocity.last_position.distance_squared_to(curr_pos) > 100.0:
		_velocity.reset(curr_pos)
		_focus.snap_to(curr_pos + Vector3(0.0, _profile.look_height, 0.0))
		var snap_pos: Vector3 = _focus.focus_point + CameraMath.spherical_offset(_orbit_state.current_yaw, _orbit_state.current_pitch, _orbit_state.current_distance) + Vector3(0.0, _profile.height * 0.55, 0.0)
		if CameraMath.is_finite_v3(snap_pos):
			global_position = snap_pos
		_has_snapped = false # force snap next frame

	_velocity.tick(curr_pos, delta)

	# 2. Combat framing (counts enemies every interval)
	_framing.tick_combat_framing(delta, curr_pos, get_tree())

	# 3. Orbit (manual + auto-follow) – now includes combat & mode for distance
	_orbit.tick(delta, _velocity, global_position, _focus.focus_point, _framing, _mode, _reduced_motion)

	# 4. Focus with prediction
	_focus.tick(curr_pos, delta, _reduced_motion)

	# 5. Desired position from framing (includes shoulder + combat boost)
	var desired_cam_pos := _framing.calculate_desired_position(_focus.focus_point, _orbit_state)

	# 6. Collision
	var world := get_world_3d()
	var collided_pos := _collision.solve(_focus.focus_point, desired_cam_pos, _orbit_state, _target, world)

	# 7. Apply follow to rig – exponential decay, snap on first frame or teleport
	var pos_smoothing := _profile.position_smoothing
	if _reduced_motion:
		pos_smoothing = _profile.reduced_motion_smoothing
	var weight := CameraMath.exp_weight(pos_smoothing, delta)
	if not _has_snapped:
		weight = 1.0
		_has_snapped = true
	_apply_follow_position(collided_pos, weight)

	# 8. Look at – with lock-on support
	_update_look_at()

	# 9. FOV – now includes mode multiplier
	_fov.tick(delta, _velocity, _framing, _mode, _camera, _reduced_motion)

	# 10. Shake – includes idle breathing when stationary
	_shake.tick(delta, _reduced_motion, _velocity.speed, _collision.is_colliding)

	# 11. Lock-on auto update from targeting component if available
	_update_lock_on_target()


func _apply_follow(weight: float, delta_for_fov: float = 0.016) -> void:
	if _profile == null or _target == null:
		return
	_velocity.tick(_target.global_position, delta_for_fov)
	_focus.tick(_target.global_position, delta_for_fov, _reduced_motion)
	var desired := _framing.calculate_desired_position(_focus.focus_point, _orbit_state)
	var collided := _collision.solve(_focus.focus_point, desired, _orbit_state, _target, get_world_3d())
	_apply_follow_position(collided, weight)
	_update_look_at()
	_fov.tick(delta_for_fov, _velocity, _framing, _mode, _camera, _reduced_motion)


func _update_look_at() -> void:
	if _camera == null or _focus.focus_point == Vector3.ZERO:
		return

	var cam_origin := _camera.global_position
	if cam_origin == Vector3.ZERO:
		cam_origin = global_position

	var look_target: Vector3
	# Lock-on mode – look at lock target + player midpoint (Zelda style)
	if _mode.is_locked():
		var lock_t := _mode.get_lock_target()
		if lock_t != null:
			var midpoint := (_focus.focus_point + lock_t.global_position) * 0.5
			midpoint.y = _focus.focus_point.y # keep height stable
			look_target = midpoint
		else:
			look_target = _framing.calculate_look_target(_focus.focus_point, _velocity)
	else:
		look_target = _framing.calculate_look_target(_focus.focus_point, _velocity)

	if not CameraMath.is_finite_v3(cam_origin) or not CameraMath.is_finite_v3(look_target):
		# Never hand Transform3D.looking_at() a NaN: the resulting basis is non-
		# orthonormal and the Camera3D would keep that transform for every frame after.
		_report_bad_camera_frame()
		return
	if cam_origin.distance_squared_to(look_target) < 0.0004:
		# Coincident eye and target (a hard snap, zero follow distance at a wall) makes
		# looking_at() degenerate; keep the previous orientation instead.
		return
	var forward := (look_target - cam_origin).normalized()
	if forward.length_squared() < 0.0001:
		return

	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.99:
		up = Vector3.FORWARD

	var target_xform := Transform3D(Basis(), cam_origin).looking_at(look_target, up)
	if not CameraMath.is_finite_transform(target_xform):
		_report_bad_camera_frame()
		return
	_camera.global_transform = target_xform


## Single writer for the rig's follow position. Rejects a non-finite solver result and
## a non-finite smoothing weight (both turn `lerp` into NaN that then latches forever),
## so a bad physics-frame can never put the camera – and with it the whole movement
## basis that reads the camera yaw – into a NaN transform.
func _apply_follow_position(next_pos: Vector3, weight: float) -> void:
	if not CameraMath.is_finite_v3(next_pos):
		_report_bad_camera_frame()
		return
	var w := 1.0 if not is_finite(weight) else clampf(weight, 0.0, 1.0)
	var next := global_position.lerp(next_pos, w)
	if not CameraMath.is_finite_v3(next):
		_report_bad_camera_frame()
		return
	next = _clamp_inside_arena(next)
	global_position = next


func _clamp_inside_arena(pos: Vector3) -> Vector3:
	var tree := get_tree()
	if tree == null:
		return pos
	var arena := tree.get_first_node_in_group("arena") as Arena
	if arena == null:
		return pos
	var half := maxf(arena.get_interior_half() - 1.35, 2.0)
	pos.x = clampf(pos.x, -half, half)
	pos.z = clampf(pos.z, -half, half)
	if not is_finite(pos.y):
		pos.y = 3.0
	else:
		pos.y = clampf(pos.y, 0.4, 18.0)
	return pos


func _report_bad_camera_frame() -> void:
	if _non_finite_reported:
		return
	_non_finite_reported = true
	push_warning("CameraRig: ignored a non-finite camera frame (follow position or look-at target); orientation held.")


func _update_lock_on_target() -> void:
	if _profile == null or not _profile.lock_on_enabled:
		return
	if _target == null:
		return
	# Try to get targeting component from player
	var targeting := _target.get_node_or_null("TargetingComponent") as TargetingComponent
	if targeting == null:
		# Also check WeaponManager or player directly for best target
		if _mode.is_locked() and _mode.get_lock_target() != null:
			# Validate distance
			var lt := _mode.get_lock_target()
			if lt is Node3D and (lt as Node3D).global_position.distance_to(_target.global_position) > _profile.lock_on_max_distance:
				_mode.set_lock_target(null)
		return

	# If the targeting component is present, use it to find the best lock target.
	var tree := get_tree()
	if tree == null:
		return
	var enemies := tree.get_nodes_in_group("enemies")
	var best := targeting.pick_best_target(enemies)
	if best is Node3D and best != null and is_instance_valid(best):
		var dist := (best as Node3D).global_position.distance_to(_target.global_position)
		if dist < _profile.lock_on_max_distance:
			# Only re-target while already locked (or when the player is aiming);
			# otherwise let manual orbit stay authoritative.
			if _mode.is_locked():
				_mode.set_lock_target(best as Node3D)
		elif _mode.is_locked():
			_mode.set_lock_target(null)


func _get_target_facing_yaw() -> float:
	if _target == null:
		return _orbit_state.current_yaw if _orbit_state != null else 0.0
	var basis := _target.global_transform.basis
	var forward := -basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return _orbit_state.current_yaw if _orbit_state != null else 0.0
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


# ------------------------------------------------------------------
# Hitstop manager & combat feedback
# ------------------------------------------------------------------

func _test_hitstop_manager() -> void:
	if _hitstop_manager != null and is_instance_valid(_hitstop_manager):
		_shake.set_hitstop_manager(_hitstop_manager as HitstopManager)
		return
	var tree := get_tree()
	if tree == null:
		return
	_hitstop_manager = tree.get_first_node_in_group("hitstop_manager")
	if _hitstop_manager == null:
		var world := tree.current_scene as Node
		if world != null:
			_hitstop_manager = world.get_node_or_null("WorldRoot/HitstopManager")
			if _hitstop_manager == null:
				_hitstop_manager = _find_node_by_class(world, "HitstopManager")
	if _hitstop_manager != null:
		_shake.set_hitstop_manager(_hitstop_manager as HitstopManager)


func _find_node_by_class(root: Node, cls_name: String) -> Node:
	if root == null:
		return null
	if root is HitstopManager:
		return root
	for child in root.get_children():
		var found := _find_node_by_class(child as Node, cls_name)
		if found != null:
			return found
	return null


func _refresh_settings() -> void:
	_reduced_motion = SaveManager.get_settings().reduced_motion if SaveManager != null else false


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
	_mode.set_mode(CameraModeController.Mode.COMBAT, 0.8)

func _on_boss_shake(_boss: Node, _id: StringName) -> void:
	add_shake(0.6, 0.5)
	_mode.set_mode(CameraModeController.Mode.BOSS, 1.0)

func _on_boss_slain_shake(_boss_id: StringName) -> void:
	add_shake(0.8, 0.6)
	_mode.set_mode(CameraModeController.Mode.EXPLORE, 0.6)

func _on_player_death_shake() -> void:
	add_shake(0.9, 0.7)


func _exit_tree() -> void:
	if EventBus == null:
		return
	if EventBus.skill_cast.is_connected(_on_skill_shake):
		EventBus.skill_cast.disconnect(_on_skill_shake)
	if EventBus.enemy_killed.is_connected(_on_kill_shake):
		EventBus.enemy_killed.disconnect(_on_kill_shake)
	if EventBus.wave_completed.is_connected(_on_wave_shake):
		EventBus.wave_completed.disconnect(_on_wave_shake)
	if EventBus.boss_spawned.is_connected(_on_boss_shake):
		EventBus.boss_spawned.disconnect(_on_boss_shake)
	if EventBus.boss_slain.is_connected(_on_boss_slain_shake):
		EventBus.boss_slain.disconnect(_on_boss_slain_shake)
	if EventBus.player_died.is_connected(_on_player_death_shake):
		EventBus.player_died.disconnect(_on_player_death_shake)


