class_name EnemyRangedState
extends EnemyState

## AI state for ranged enemies: strafe at preferred distance, then plant, telegraph
## (flash + windup sound) and fire a projectile volley through the shared
## ProjectilePool. Improvements over the base orbit:
##  - kites hard when the player closes inside ~55% of the preferred distance,
##    cancelling a windup rather than firing into melee;
##  - volleys lead a moving target slightly (distance / projectile speed based);
##  - the windup telegraphs through EnemyBase feedback/audio hooks.
## Falls back to chasing when the target is far outside weapon range; missing
## projectile pools never crash, they only skip the volley.
##
## Config surface (read from EnemyConfig when present, else defaults):
## ranged_range, ranged_cooldown, ranged_windup, projectile_speed,
## projectile_damage_scale, projectile_spread, preferred_distance, strafe_speed.

const KEY := &"ranged"

const KITE_FACTOR := 0.55
const LEAD_FACTOR := 0.6

var _cooldown := 0.0
var _windup := 0.0
var _firing := false
var _strafe_dir := 1.0
var _strafe_timer := 0.0
## Shots fired since entering this state; the first is the deliberately loose
## "warning shot" (see _fire).
var _shot_index := 0


func _init() -> void:
	super._init(KEY)


func enter(host: EnemyBase) -> void:
	_cooldown = _cfg(host, &"ranged_cooldown", 2.0) * 0.5
	_windup = 0.0
	_firing = false
	_strafe_timer = 0.0
	_shot_index = 0


func exit(host: EnemyBase) -> void:
	host.set_desired_move(Vector3.ZERO, 0.0)


func physics_update(host: EnemyBase, delta: float) -> void:
	var target := host.get_move_target()
	if target == null:
		host.state_machine_change_to(&"idle")
		return
	_cooldown -= delta
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = 1.2
		_strafe_dir = -_strafe_dir
	var to: Vector3 = target.global_position - host.global_position
	to.y = 0.0
	var dist := to.length()
	var preferred := _cfg(host, &"preferred_distance", 9.0)
	var max_range := _cfg(host, &"ranged_range", 14.0)
	host.face_target(target)
	if dist > max_range * 1.15:
		# Too far: close the distance like a chaser.
		var dir := host.get_navigation_direction(to.normalized() if dist > 0.01 else Vector3.FORWARD)
		host.set_desired_move(dir, host.get_effective_speed())
		return
	# Kite: player too close -> back away at full speed, abort any windup.
	if dist < preferred * KITE_FACTOR:
		if _firing:
			_firing = false
			_windup = 0.0
		var away := -to.normalized() if dist > 0.01 else Vector3.BACK
		host.set_desired_move(away, host.get_effective_speed())
		return
	if _firing:
		_windup -= delta
		host.set_desired_move(Vector3.ZERO, 0.0)
		if _windup <= 0.0:
			_firing = false
			_fire(host, target)
		return
	# Humans do not shoot through pillars: without line of sight the enemy
	# scrambles for a cleaner angle instead of firing blind.
	var has_los := host.has_line_of_sight_to(target.global_position)
	if _cooldown <= 0.0 and dist <= max_range and has_los:
		_firing = true
		_windup = _cfg(host, &"ranged_windup", 0.5)
		host.set_desired_move(Vector3.ZERO, 0.0)
		# Telegraph the volley so it can be dodged/side-stepped.
		host.play_telegraph_feedback()
		host.play_windup_sound()
		return
	# Strafe orbit at preferred distance (drift in/out + sideways); faster
	# when the angle is blocked, so repositioning reads as intent.
	var radial := Vector3.ZERO
	if dist > 0.01:
		var outward := to.normalized()
		if dist > preferred + 1.0:
			radial = outward
		elif dist < preferred - 1.0:
			radial = -outward
	var tangent := Vector3(-to.z, 0.0, to.x).normalized() * _strafe_dir if dist > 0.01 else Vector3.ZERO
	var move := (radial * 0.7 + tangent * 0.7)
	if move.length_squared() > 1.0:
		move = move.normalized()
	var strafe_speed := _cfg(host, &"strafe_speed", 0.6)
	if not has_los:
		strafe_speed = maxf(strafe_speed, 0.9)
	host.set_desired_move(move, host.get_effective_speed() * strafe_speed)


func _fire(host: EnemyBase, target: Node3D) -> void:
	_cooldown = _cfg(host, &"ranged_cooldown", 2.0)
	var pools := host.get_tree().get_nodes_in_group("projectile_pool") if host.is_inside_tree() else []
	if pools.is_empty():
		return
	var pool := pools[0] as ProjectilePool
	var from: Vector3 = host.global_position + Vector3(0, 1.2, 0)
	var aim_point: Vector3 = _lead_point(host, target, from)
	var aim: Vector3 = aim_point - from
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	# Human aim (research, docs/ENEMY_AI_RESEARCH.md): spread grows with
	# distance and the individual's inaccuracy, and the FIRST shot after
	# spotting is deliberately looser — a warning the player can dodge, not a
	# laser from the first frame.
	var max_range_los := _cfg(host, &"ranged_range", 14.0)
	var skill := host.get_aim_skill()
	var err_rad := (1.0 - skill) * 0.22 * clampf(from.distance_to(target.global_position) / max_range_los, 0.0, 1.0)
	if _shot_index == 0:
		err_rad *= 1.7
	_shot_index += 1
	if err_rad > 0.001:
		var h := hash(Vector3(float(host.get_instance_id()), float(_shot_index), 0.0))
		var t := fposmodf(float(h), 1000.0) / 1000.0 * 2.0 - 1.0  # deterministic -1..1
		aim = aim.rotated(Vector3.UP, err_rad * t)
	var count := int(_cfg(host, &"projectile_count", 1.0))
	var dirs := RangedResolver.spread_directions(aim, count, _cfg(host, &"projectile_spread", 8.0))
	var speed := _cfg(host, &"projectile_speed", 12.0)
	pool.fire_volley({
		"team": Projectile.TEAM_ENEMY,
		"origin": from,
		"speed": speed,
		"damage": host.get_effective_attack_damage() * _cfg(host, &"projectile_damage_scale", 0.8),
		"knockback": 3.0,
		"pierce": 0,
		"max_distance": _cfg(host, &"ranged_range", 14.0) + 2.0,
		"lifetime": 2.0,
		"source": host,
		"source_id": host.get_archetype_id(),
	}, dirs)


## Lead a moving target proportionally to the projectile's time of flight.
func _lead_point(host: EnemyBase, target: Node3D, from: Vector3) -> Vector3:
	var point: Vector3 = target.global_position
	var v: Variant = target.get("velocity")
	if v == null or not (v is Vector3):
		return point
	var flat_vel := v as Vector3
	flat_vel.y = 0.0
	if flat_vel.length_squared() < 0.25:
		return point
	var speed := _cfg(host, &"projectile_speed", 12.0)
	var flight := from.distance_to(point) / maxf(speed, 0.01)
	return point + flat_vel * (flight * LEAD_FACTOR)


## Read an optional numeric field from the host config with a default.
func _cfg(host: EnemyBase, key: StringName, fallback: float) -> float:
	var cfg := host.get_config()
	if cfg == null:
		return fallback
	var v: Variant = cfg.get(String(key))
	if v is float or v is int:
		return float(v)
	return fallback

## Hardened: validate ranged target and cooldown.
func _validated_ranged(cd: float, target: Node) -> Dictionary:
	if not is_finite(cd) or cd < 0.0:
		cd = 1.0
	cd = clampf(cd, 0.05, 10.0)
	var valid := target != null and is_instance_valid(target) and target.is_inside_tree()
	return {"cd": cd, "valid": valid}

