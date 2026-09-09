extends Node
class_name CharacterController

## Converts movement intent into grounded, collision-aware motion and facing for the
## owning CharacterBody3D. Pure-ish with respect to timing: physics uses delta so a
## fixed/fake clock produces deterministic results.

@export var move_speed: float = 6.0
@export var acceleration: float = 24.0
@export var deceleration: float = 30.0
@export var gravity: float = 18.0
@export var turn_speed: float = 14.0  # shared combat/visual yaw smoothing (radians/sec)

var _last_move_input := Vector2.ZERO
var _owner_body: CharacterBody3D = null
var _weapons: WeaponManager
var _non_finite_reported := false
# Movement is never locked by a legacy attack controller: the single authority
# for attack-driven movement locking is WeaponInstance.phase == WINDUP.


func _ready() -> void:
	_owner_body = get_parent() as CharacterBody3D
	_weapons = get_parent().get_node_or_null("WeaponManager") as WeaponManager
	if _owner_body == null:
		push_warning("CharacterController parent is not a CharacterBody3D")


## Advance the body for one physics step. move_input is a normalized joystick/axis
## Vector2 in screen space (x=strafe, y=forward as perceived on screen).
func tick(move_input: Vector2, delta: float) -> void:
	if _owner_body == null:
		return
	if not is_finite(delta) or delta <= 0.0:
		# A zero/NaN delta (tab restore, engine hickup) turns every rate below into
		# inf/NaN, which is unrecoverable once integrated into velocity. Skip the step.
		return
	if not _is_finite_v2(move_input):
		# A poisoned stick/axis sample must never reach the body. One non-finite
		# component written into CharacterBody3D is integrated into global_position,
		# the body's AABB goes NaN, and the physics/renderer abort a few frames later —
		# exactly the reported "crashes a few steps after moving". Drop the sample and
		# hold position; _report_non_finite keeps the real source visible in the log.
		_report_non_finite("tick input")
		_last_move_input = Vector2.ZERO
		_apply_velocity(_clean_velocity(_owner_body.velocity))
		return
	_last_move_input = _sanitize(move_input)

	var vel := _clean_velocity(_owner_body.velocity)
	if not _owner_body.is_on_floor():
		vel.y -= gravity * delta

	var dir := _screen_dir_to_world(_last_move_input)
	var target_h := dir * move_speed
	var inst := _weapons.active_instance() if _weapons != null else null
	var locked := inst != null and inst.phase == WeaponInstance.PHASE_WINDUP
	if dir.length_squared() > 0.001:
		vel.x = move_toward(vel.x, target_h.x, acceleration * delta)
		vel.z = move_toward(vel.z, target_h.z, acceleration * delta)
		if not locked:
			_turn_toward(dir, delta)
	else:
		vel.x = move_toward(vel.x, 0.0, deceleration * delta)
		vel.z = move_toward(vel.z, 0.0, deceleration * delta)

	_apply_velocity(vel)


## Horizontal ground movement basis relative to the camera rig yaw (screen-forwards
## maps to camera forward). Preserves analog magnitude in world XZ.
func _screen_dir_to_world(v: Vector2) -> Vector3:
	if not _is_finite_v2(v):
		return Vector3.ZERO
	var cam_yaw := _camera_yaw()
	var forward := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(-forward.z, 0.0, forward.x)
	var dir3 := (-forward * v.y + right * v.x)
	if not _is_finite_v3(dir3):
		return Vector3.ZERO
	if dir3.length_squared() > 0.0001:
		dir3 = dir3.normalized() * minf(v.length(), 1.0)
	return dir3


## Public helper so other systems (e.g. the DodgeController owner) can turn a screen
## joystick vector into a world XZ direction using the same camera-relative basis.
func screen_to_world_dir(v: Vector2) -> Vector3:
	return _screen_dir_to_world(v)


func _camera_yaw() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var cam := vp.get_camera_3d()
	if cam == null:
		return 0.0
	# A camera whose basis went non-finite (degenerate look-at) would otherwise inject
	# NaN into the entire movement basis; treat it as "camera not rotated".
	var yaw := cam.global_transform.basis.get_euler().y
	return yaw if is_finite(yaw) else 0.0


func _turn_toward(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001 or not _is_finite_v3(dir) or not is_finite(delta):
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	if not is_finite(target_yaw):
		return
	# Assign the whole rotation vector: writing one Euler component of a read-mostly
	# property can hand back a partially-recomposed transform.
	var rot := _owner_body.global_rotation
	rot.y = rotate_toward(rot.y, target_yaw, turn_speed * delta)
	if _is_finite_v3(rot):
		_owner_body.global_rotation = rot


func face_direction(direction: Vector3) -> void:
	if _owner_body == null or direction.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	if not is_finite(target_yaw):
		return
	var rot := _owner_body.global_rotation
	rot.y = target_yaw
	if _is_finite_v3(rot):
		_owner_body.global_rotation = rot


## Dash/skill intent handler — authoritative movement for dash-like bursts.
## SkillController and DodgeController request dash intent; this controller
## performs the actual grounded move_and_slide so gameplay stays single-authority.
## Preserves distance/timing via caller-supplied speed; collision and gravity handled here.
func apply_dash(direction: Vector3, speed: float, delta: float) -> void:
	if _owner_body == null or delta <= 0.0:
		return
	if not _is_finite_v3(direction) or not is_finite(speed) or not is_finite(delta):
		# A dash is the one place velocity is assigned outright (no move_toward
		# limiting), so an inf/NaN speed would be written straight into the body.
		_report_non_finite("dash inputs")
		return
	var vel := _clean_velocity(_owner_body.velocity)
	if not _owner_body.is_on_floor():
		vel.y -= gravity * delta
	vel.x = direction.x * speed
	vel.z = direction.z * speed
	_apply_velocity(vel)
	# Face the dash direction for readability, but don't lock windup attacks.
	var inst := _weapons.active_instance() if _weapons != null else null
	var locked := inst != null and inst.phase == WeaponInstance.PHASE_WINDUP
	if not locked and direction.length_squared() > 0.0001:
		_turn_toward(direction, delta)


## THE single place velocity reaches the physics server: both tick() and apply_dash()
## go through it, so a non-finite component is neutralised here instead of being
## integrated into global_position (where it would survive and crash seconds later).
func _apply_velocity(vel: Vector3) -> void:
	if not _is_finite_v3(vel):
		vel = Vector3.ZERO
	_owner_body.velocity = vel
	_owner_body.move_and_slide()
	# move_and_slide() can hand back non-finite velocity when a floor/slope query
	# degenerates, and a bad collider can push NaN into the transform. Repair, never
	# propagate: recovering per axis keeps the hero where they were instead of
	# teleporting them to the arena origin.
	var after := _clean_velocity(_owner_body.velocity)
	if not _is_finite_v3(_owner_body.global_position):
		_report_non_finite("body transform")
		var pos := _owner_body.global_position
		_owner_body.global_position = Vector3(
			0.0 if not is_finite(pos.x) else clampf(pos.x, -1.0e4, 1.0e4),
			0.0 if not is_finite(pos.y) else pos.y,
			0.0 if not is_finite(pos.z) else clampf(pos.z, -1.0e4, 1.0e4))
		after = Vector3.ZERO
		# Recovering a poisoned transform is a teleport: the hero must be AT the
		# repaired position on this frame, not interpolated towards it.
		_owner_body.reset_physics_interpolation()
	_owner_body.velocity = after


## Repair a velocity read from the body before it is integrated any further.
func _clean_velocity(vel: Vector3) -> Vector3:
	return Vector3(
		0.0 if not is_finite(vel.x) else vel.x,
		0.0 if not is_finite(vel.y) else vel.y,
		0.0 if not is_finite(vel.z) else vel.z)


func _is_finite_v2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _is_finite_v3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## Warn once per process. A silent guard would hide which signal was bad; a hard
## error/abort is exactly what we must not do on a phone mid-run.
func _report_non_finite(where: String) -> void:
	if _non_finite_reported:
		return
	_non_finite_reported = true
	push_warning("CharacterController: refused non-finite %s; locomotion held steady instead of crashing." % where)


func _sanitize(v: Vector2) -> Vector2:
	if not _is_finite_v2(v):
		return Vector2.ZERO
	var len_sq := v.length_squared()
	if len_sq > 1.0:
		return v.normalized()
	return v


func is_moving() -> bool:
	return _last_move_input.length_squared() > 0.001


func set_move_speed(value: float) -> void:
	# clampf (not maxf) so an inf/negative stat from progression or a legacy save
	# cannot make `dir * move_speed` overflow the velocity.
	move_speed = 0.0 if not is_finite(value) else clampf(value, 0.0, 40.0)


func get_debug_snapshot() -> Dictionary:
	return {
		"move_input": Vector2(_last_move_input.x, _last_move_input.y),
		"is_moving": is_moving(),
		"move_speed": move_speed,
	}


## Input callbacks may stop intent, but must never integrate physics a second time.
func stop() -> void:
	_last_move_input = Vector2.ZERO
	if _owner_body != null:
		# Zero XZ on a *repaired* copy: assigning component-wise onto a velocity that is
		# already non-finite would keep the poisoned axes alive through the stop.
		var vel := _clean_velocity(_owner_body.velocity)
		vel.x = 0.0
		vel.z = 0.0
		_owner_body.velocity = vel
